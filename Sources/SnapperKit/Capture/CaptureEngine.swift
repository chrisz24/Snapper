import Foundation

public enum CaptureError: Error, LocalizedError {
    case screenRecordingDenied
    case launchFailed(String)
    case outputMissing
    case unreadableImage

    public var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            "Snapper needs Screen Recording permission to capture the screen."
        case .launchFailed(let detail):
            "Could not start the capture: \(detail)"
        case .outputMissing:
            "The capture produced no file."
        case .unreadableImage:
            "The captured file could not be read as an image."
        }
    }
}

/// Abstracts *how* pixels get grabbed.
///
/// v1 drives the system picker via `screencapture`, which buys the exact crosshair, magnifier,
/// dimension readout, space-to-toggle, and Esc-to-cancel behaviour users already know, across all
/// displays. A custom ScreenCaptureKit overlay can be slotted in behind this protocol later.
public protocol CaptureEngine: Sendable {
    /// Returns nil when the user cancelled (Esc).
    func capture(_ request: CaptureRequest) async throws -> CaptureResult?
}
