import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Drives `/usr/sbin/screencapture`, which supplies the system selection UI.
public struct ScreencaptureCLIEngine: CaptureEngine {
    public static let executable = URL(fileURLWithPath: "/usr/sbin/screencapture")

    public init() {}

    public func capture(_ request: CaptureRequest) async throws -> CaptureResult? {
        let args = CaptureArgumentBuilder.arguments(for: request)

        // Clear any stale file so a cancelled capture can't be mistaken for a successful one.
        try? FileManager.default.removeItem(at: request.outputURL)

        let status = try await runProcess(arguments: args)

        // Esc during selection exits non-zero and writes nothing. Belt and braces: some paths
        // exit zero but still produce no file.
        guard status == 0, FileManager.default.fileExists(atPath: request.outputURL.path) else {
            try? FileManager.default.removeItem(at: request.outputURL)
            return nil
        }

        let (image, scale) = try Self.loadImage(at: request.outputURL)
        return CaptureResult(
            fileURL: request.outputURL,
            image: image,
            scale: scale,
            mode: request.mode,
            isTemporary: true
        )
    }

    private func runProcess(arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = Self.executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: CaptureError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Reads the capture back, recovering the Retina scale factor from the DPI metadata
    /// `screencapture` embeds (72 dpi = 1×, 144 dpi = 2×).
    ///
    /// The decode is forced to happen now, rather than lazily on first use. A CGImage created from
    /// a file-backed source keeps reading from that file, so the moment the capture is moved into
    /// the user's save folder the image would quietly go dead — and every later encode (clipboard,
    /// format conversion, markup, thumbnails) would fail with no error to show for it.
    public static func loadImage(at url: URL) throws -> (CGImage, CGFloat) {
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary)
        else { throw CaptureError.unreadableImage }

        var scale: CGFloat = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let dpi = props[kCGImagePropertyDPIWidth] as? CGFloat, dpi > 0 {
            scale = max(1, (dpi / 72).rounded())
        }
        return (image, scale)
    }
}
