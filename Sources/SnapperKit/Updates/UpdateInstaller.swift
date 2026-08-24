import Foundation
import AppKit
import Security

/// Downloads an update and hands it to macOS's own Installer.
///
/// The important part of this file is not the download — it is everything between the download
/// finishing and the package being opened. A downloaded installer is arbitrary code that will run
/// with administrator rights, so it is checked three ways first:
///
///   1. It is signed with a Developer ID Installer certificate.
///   2. That certificate belongs to **the same team that signed the running copy of Snapper**, read
///      from our own signature rather than hard-coded, so a fork checks against its own team.
///   3. Gatekeeper accepts it, which is what proves it was notarized by Apple.
///
/// Failing any of those, the file is deleted and nothing is opened. Skipping these and simply
/// opening whatever arrived would make the updater a way to run code on the user's machine for
/// anyone who could interfere with the download.
@MainActor
public final class UpdateInstaller: ObservableObject {

    public enum Progress: Equatable, Sendable {
        case downloading(fraction: Double, received: Int64, expected: Int64)
        case verifying
    }

    public enum Failure: LocalizedError, Equatable {
        case notInstallable
        case transfer(String)
        case unsigned
        case wrongTeam(found: String, expected: String)
        case notNotarized(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .notInstallable:
                "That release has no installer package attached."
            case .transfer(let detail):
                "The download did not finish — \(detail)"
            case .unsigned:
                "The downloaded installer is not signed with a Developer ID. It was discarded."
            case .wrongTeam(let found, let expected):
                "The downloaded installer is signed by team \(found), not \(expected). It was discarded."
            case .notNotarized(let detail):
                "macOS would not accept the downloaded installer — \(detail). It was discarded."
            case .cancelled:
                "Cancelled."
            }
        }
    }

    @Published public private(set) var progress: Progress?

    private var task: Task<Void, Never>?
    private let session: URLSession

    public init(session: URLSession = UpdateChecker.makeSession()) {
        self.session = session
    }

    public var isWorking: Bool { progress != nil }

    /// Downloads and verifies. Returns the package, ready to open.
    public func fetch(_ release: GitHubRelease) async -> Result<URL, Failure> {
        guard let asset = release.asset, asset.name.lowercased().hasSuffix(".pkg") else {
            return .failure(.notInstallable)
        }

        defer { progress = nil }
        progress = .downloading(fraction: 0, received: 0, expected: Int64(asset.byteCount))

        let downloaded: URL
        do {
            downloaded = try await download(asset)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.transfer(error.localizedDescription))
        }

        progress = .verifying
        do {
            try await Self.verify(downloaded)
        } catch let failure as Failure {
            // Anything that fails verification is deleted rather than left in a temporary folder
            // where it could still be opened by hand.
            try? FileManager.default.removeItem(at: downloaded)
            return .failure(failure)
        } catch {
            try? FileManager.default.removeItem(at: downloaded)
            return .failure(.notNotarized(error.localizedDescription))
        }

        return .success(downloaded)
    }

    public func cancel() {
        task?.cancel()
        task = nil
        progress = nil
    }

    // MARK: - Download

    private func download(_ asset: GitHubRelease.Asset) async throws -> URL {
        let reporter = ProgressReporter { [weak self] fraction, received, expected in
            Task { @MainActor in
                guard let self, self.progress != nil else { return }
                self.progress = .downloading(fraction: fraction, received: received, expected: expected)
            }
        }

        // GitHub redirects release downloads to a storage host; the default redirect handling is
        // what follows it.
        let (temporary, response) = try await session.download(from: asset.url, delegate: reporter)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: temporary)
            throw Failure.transfer("GitHub replied with HTTP \(http.statusCode)")
        }

        // URLSession's temporary file has no extension, and both `pkgutil` and Installer decide what
        // a file is from its name. It also has to leave the location URLSession will clean up.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Snapper-Update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    // MARK: - Verification

    /// The team that signed the running app, read from its own signature. Nil for an unsigned or
    /// ad-hoc build, which is the case when running straight out of `swift build`.
    public static var runningTeamIdentifier: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }

        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func verify(_ package: URL) async throws {
        let signature = try run("/usr/sbin/pkgutil", ["--check-signature", package.path])
        guard let team = Self.teamIdentifier(inPkgutilOutput: signature.output) else {
            throw Failure.unsigned
        }

        // Pinning to our own team is what makes this meaningful. Accepting any Developer ID would
        // accept a package signed by anyone with an Apple developer account.
        if let expected = runningTeamIdentifier, team != expected {
            throw Failure.wrongTeam(found: team, expected: expected)
        }

        // Gatekeeper's own assessment, which is what proves Apple notarized it.
        let assessment = try run("/usr/sbin/spctl", ["--assess", "--type", "install", "-vv", package.path])
        guard assessment.status == 0, assessment.output.contains("accepted") else {
            let reason = assessment.output
                .split(separator: "\n").last.map(String.init) ?? "rejected"
            throw Failure.notNotarized(reason.trimmingCharacters(in: .whitespaces))
        }
    }

    /// Pulls the team out of `Developer ID Installer: Some Name (TEAMID)`.
    ///
    /// Only the first certificate in the chain is considered: the intermediate and root are Apple's
    /// and carry no team, and scanning the whole output would match the wrong line.
    ///
    /// Pure string work with no actor requirement, and public so the suite can exercise it against
    /// real `pkgutil` output — this is the check that decides whether downloaded code gets run.
    public nonisolated static func teamIdentifier(inPkgutilOutput output: String) -> String? {
        guard let line = output
            .split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.contains("Developer ID Installer:") })
        else { return nil }

        guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"),
              open < close else { return nil }
        let team = String(line[line.index(after: open)..<close])
        return team.isEmpty ? nil : team
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Read before waiting: a full pipe buffer would otherwise deadlock the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Bridges `URLSessionDownloadDelegate` progress onto a closure.
private final class ProgressReporter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double, Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Double, Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // A server that sends no Content-Length reports -1; showing a fraction from that would draw
        // a bar that runs backwards.
        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        onProgress(fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }

    /// Required by the protocol; the async `download(from:delegate:)` returns the file itself.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
