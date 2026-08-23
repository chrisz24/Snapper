import Foundation
import UniformTypeIdentifiers

/// Output image format. Raw values double as `screencapture -t` arguments.
public enum ImageFormat: String, CaseIterable, Codable, Sendable {
    case png, jpg, heic, tiff, pdf

    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .pdf: "PDF"
        }
    }

    public var contentType: UTType {
        switch self {
        case .png: .png
        case .jpg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .pdf: .pdf
        }
    }
}

public enum PreviewCorner: String, CaseIterable, Codable, Sendable {
    case bottomRight, bottomLeft, topRight, topLeft

    public var displayName: String {
        switch self {
        case .bottomRight: "Bottom Right"
        case .bottomLeft: "Bottom Left"
        case .topRight: "Top Right"
        case .topLeft: "Top Left"
        }
    }
}

/// How recognized lines are stitched back together. This is the "linebreaks or not" setting.
public enum LineBreakMode: String, CaseIterable, Codable, Sendable {
    /// Every recognized line becomes its own line. Faithful to the layout.
    case preserveLines
    /// Soft-wrapped lines rejoin into paragraphs; real paragraph breaks survive.
    case smartParagraphs
    /// Everything collapses onto one line.
    case singleLine

    public var displayName: String {
        switch self {
        case .preserveLines: "Preserve line breaks"
        case .smartParagraphs: "Join wrapped lines into paragraphs"
        case .singleLine: "Single line"
        }
    }

    public var explanation: String {
        switch self {
        case .preserveLines:
            "Keeps the text laid out exactly as it appeared on screen."
        case .smartParagraphs:
            "Uses macOS's own wrap detection to rejoin lines that were only broken to fit the width, while keeping real paragraph breaks and headings."
        case .singleLine:
            "Collapses everything into one continuous line. Useful for URLs, codes, and IDs."
        }
    }
}

public enum RecognitionLevelSetting: String, CaseIterable, Codable, Sendable {
    case accurate, fast

    public var displayName: String {
        switch self {
        case .accurate: "Accurate"
        case .fast: "Fast"
        }
    }
}

/// Controls when quick-action shortcuts are listening.
public enum QuickActionActivation: String, CaseIterable, Codable, Sendable {
    /// Shortcuts are grabbed system-wide for the preview's lifetime.
    case global
    /// Shortcuts are only grabbed while the pointer is over the preview.
    case hoverOnly

    public var displayName: String {
        switch self {
        case .global: "Anywhere, while the preview is visible"
        case .hoverOnly: "Only while pointing at the preview"
        }
    }
}
