import Foundation
import CoreGraphics

public enum CaptureMode: Equatable, Sendable {
    /// Interactive drag-a-region, with space to toggle to window mode — same as ⌘⇧4.
    case region
    /// Interactive, starting in window-picker mode — same as ⌘⇧4 then space.
    case window
    /// Non-interactive whole display. `displayIndex` is 1-based; 1 is the main display.
    case fullScreen(displayIndex: Int)
    /// Same selection UI as `.region`, but the result is destined for text recognition.
    case regionForOCR

    public var isInteractive: Bool {
        switch self {
        case .region, .window, .regionForOCR: true
        case .fullScreen: false
        }
    }

    public var isForOCR: Bool { self == .regionForOCR }
}

public struct CaptureOptions: Equatable, Sendable {
    public var format: ImageFormat
    public var includeCursor: Bool
    public var includeWindowShadow: Bool
    public var delaySeconds: Int
    /// Suppresses the shutter sound.
    public var silent: Bool

    public init(
        format: ImageFormat = .png,
        includeCursor: Bool = false,
        includeWindowShadow: Bool = true,
        delaySeconds: Int = 0,
        silent: Bool = false
    ) {
        self.format = format
        self.includeCursor = includeCursor
        self.includeWindowShadow = includeWindowShadow
        self.delaySeconds = delaySeconds
        self.silent = silent
    }
}

public struct CaptureRequest: Equatable, Sendable {
    public var mode: CaptureMode
    public var options: CaptureOptions
    public var outputURL: URL

    public init(mode: CaptureMode, options: CaptureOptions = CaptureOptions(), outputURL: URL) {
        self.mode = mode
        self.options = options
        self.outputURL = outputURL
    }

    /// Captures always land on disk as PNG, regardless of the user's chosen format.
    ///
    /// Two reasons. Lossless input matters for OCR — JPEG ringing around glyph edges measurably
    /// hurts recognition. And PNG is always readable back into a CGImage, whereas capturing
    /// straight to PDF (or HEIC) would leave the preview, clipboard, and OCR paths holding a file
    /// they cannot decode. `options.format` is applied by `ImageWriter` when the capture is saved
    /// to its final destination.
    public static let captureFormat: ImageFormat = .png
}

public struct CaptureResult: Sendable {
    public var fileURL: URL
    public var image: CGImage
    public var scale: CGFloat
    public var mode: CaptureMode
    public var createdAt: Date
    /// True while the file still lives in scratch rather than the user's save folder.
    public var isTemporary: Bool

    public init(
        fileURL: URL,
        image: CGImage,
        scale: CGFloat,
        mode: CaptureMode,
        createdAt: Date = Date(),
        isTemporary: Bool
    ) {
        self.fileURL = fileURL
        self.image = image
        self.scale = scale
        self.mode = mode
        self.createdAt = createdAt
        self.isTemporary = isTemporary
    }

    public var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    /// Logical size — what the region measured on screen.
    public var pointSize: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
}
