import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// Encodes a CGImage to disk (or to Data) in the user's chosen delivery format.
public enum ImageWriter {

    public enum WriteError: Error, LocalizedError {
        case unsupportedDestination(ImageFormat)
        case encodingFailed

        public var errorDescription: String? {
            switch self {
            case .unsupportedDestination(let f): "Cannot write \(f.displayName) files."
            case .encodingFailed: "The image could not be encoded."
            }
        }
    }

    /// JPEG/HEIC quality, 0...1.
    public static var compressionQuality: CGFloat = 0.9

    public static func write(_ image: CGImage, to url: URL, format: ImageFormat, scale: CGFloat) throws {
        if format == .pdf {
            try writePDF(image, to: url, scale: scale)
            return
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.contentType.identifier as CFString, 1, nil
        ) else { throw WriteError.unsupportedDestination(format) }

        // Preserve DPI so a 2× capture opens at its true logical size rather than double.
        let dpi = 72 * scale
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WriteError.encodingFailed }
    }

    public static func pngData(_ image: CGImage, scale: CGFloat = 1) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        let dpi = 72 * scale
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func writePDF(_ image: CGImage, to url: URL, scale: CGFloat) throws {
        var mediaBox = CGRect(
            x: 0, y: 0,
            width: CGFloat(image.width) / scale,
            height: CGFloat(image.height) / scale
        )
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw WriteError.unsupportedDestination(.pdf)
        }
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
    }
}
