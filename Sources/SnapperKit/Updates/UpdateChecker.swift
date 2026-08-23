import Foundation

/// Asks GitHub whether a newer release exists.
///
/// Nothing is downloaded or installed here. The app is distributed as a notarized disk image, and
/// a menu bar app that replaces its own bundle while running has to hand off to a helper to do it
/// — so "update" means "open the download", and macOS's own install flow takes it from there.
///
/// Only the public Releases API is used, so no token is involved and nothing about the machine is
/// sent beyond what any HTTP request carries.
@MainActor
public final class UpdateChecker: ObservableObject {
    public enum Outcome: Equatable, Sendable {
        case upToDate
        case updateAvailable(GitHubRelease)
        case failed(UpdateError)
    }

    /// How long after a check before another one is due. Only applies to automatic checks; the
    /// menu item always asks.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    @Published public private(set) var isChecking = false
    @Published public private(set) var lastOutcome: Outcome?

    private let settings: SettingsStore
    private let session: URLSession
    private let current: AppVersion

    public init(
        settings: SettingsStore,
        session: URLSession = UpdateChecker.makeSession(),
        currentVersion: AppVersion? = AppInfo.currentVersion
    ) {
        self.settings = settings
        self.session = session
        // A binary running outside a bundle reports its version as "dev", which will not parse.
        // Treating that as 0.0.0 means an unreleased build always looks out of date, which is
        // true, rather than silently never checking.
        self.current = currentVersion ?? AppVersion("0.0.0")!
    }

    /// No disk cache, and short timeouts: this runs unattended at launch and must never be the
    /// reason something feels slow.
    public nonisolated static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    public var currentVersion: AppVersion { current }

    public var lastCheckedAt: Date? {
        settings.lastUpdateCheck > 0 ? Date(timeIntervalSince1970: settings.lastUpdateCheck) : nil
    }

    public var isCheckDue: Bool {
        guard let last = lastCheckedAt else { return true }
        return Date().timeIntervalSince(last) >= Self.checkInterval
    }

    // MARK: - Checking

    /// A check the user asked for. Reports both outcomes, and ignores a skipped version — having
    /// skipped 0.3.0 should not make "Check for Updates…" claim you are up to date.
    public func check() async -> Outcome {
        await run(honouringSkips: false)
    }

    /// The automatic check. Returns nil without touching the network when it is switched off or
    /// not yet due, so the caller can tell "nothing to say" from "checked, nothing new".
    public func checkIfDue() async -> Outcome? {
        guard settings.automaticUpdateChecks, isCheckDue else { return nil }
        return await run(honouringSkips: true)
    }

    private func run(honouringSkips: Bool) async -> Outcome {
        isChecking = true
        defer { isChecking = false }

        let outcome: Outcome
        do {
            let releases = try await fetchReleases()
            // Record the attempt only when GitHub actually answered. A failed check should be
            // retried at the next opportunity, not deferred for another day.
            settings.lastUpdateCheck = Date().timeIntervalSince1970

            let skipped = honouringSkips ? settings.skippedUpdateVersion : ""
            if let newest = UpdateResolver.newest(in: releases,
                                                  includePrereleases: settings.includePrereleaseUpdates),
               UpdateResolver.isWorthOffering(newest, current: current, skipping: skipped) {
                outcome = .updateAvailable(newest)
            } else {
                outcome = .upToDate
            }
        } catch let error as UpdateError {
            outcome = .failed(error)
        } catch {
            outcome = .failed(.offline(error.localizedDescription))
        }

        lastOutcome = outcome
        return outcome
    }

    /// Records that this exact version should stop being offered. A later one still will be.
    public func skip(_ release: GitHubRelease) {
        settings.skippedUpdateVersion = release.version.displayString
    }

    public func clearSkippedVersion() {
        settings.skippedUpdateVersion = ""
    }

    public var skippedVersion: String { settings.skippedUpdateVersion }

    // MARK: - Networking

    private func fetchReleases() async throws -> [GitHubRelease] {
        var request = URLRequest(url: AppInfo.releasesAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub rejects API requests without one.
        request.setValue("\(AppInfo.name)/\(AppInfo.version) (+\(AppInfo.repositoryURL.absoluteString))",
                         forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw UpdateError.offline(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw UpdateError.malformedFeed }
        switch http.statusCode {
        case 200:
            break
        case 403, 429:
            // Both are used for rate limiting; the header is what distinguishes it from a genuine
            // refusal, which on a public repo should not happen.
            if http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
                throw UpdateError.rateLimited
            }
            throw UpdateError.badResponse(http.statusCode)
        case 404:
            // The repository is missing, private, or renamed — not merely short of releases.
            throw UpdateError.repositoryNotFound
        default:
            throw UpdateError.badResponse(http.statusCode)
        }

        let releases = try GitHubRelease.decodeFeed(data)
        guard !releases.isEmpty else { throw UpdateError.noReleasesPublished }
        return releases
    }
}
