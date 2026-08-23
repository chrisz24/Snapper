import Foundation
import AppKit

/// Puts a capture on the pasteboard in every flavour receiving apps actually ask for.
public enum ClipboardWriter {

    /// Writes the capture as a single pasteboard item carrying several representations.
    ///
    /// The representations matter: some apps paste TIFF, some prefer PNG, and Finder or a file
    /// field wants the URL. Declaring all of them means ⌘V does the right thing everywhere rather
    /// than only in the app it was tested against.
    ///
    /// Crucially they all belong to **one** item. Writing the image and the file URL as two
    /// separate items made apps that paste the whole pasteboard insert the picture twice — once
    /// from the image data and once from the file. One item with three types is one paste, and the
    /// receiver picks whichever representation it understands best.
    public static func write(_ result: CaptureResult) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        var wroteImage = false

        // PNG first: it is listed ahead of the file URL so apps that scan in order lean towards
        // pasting the picture inline rather than attaching a file.
        if let pngData = ImageWriter.pngData(result.image, scale: result.scale) {
            item.setData(pngData, forType: .png)
            if let tiff = NSImage(data: pngData)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            wroteImage = true
        }

        if FileManager.default.fileExists(atPath: result.fileURL.path) {
            item.setString(result.fileURL.absoluteString, forType: .fileURL)
        }

        guard wroteImage || item.types.contains(.fileURL) else {
            // Encoding failed and there is no file to fall back on; hand over the image directly.
            pasteboard.writeObjects([NSImage(cgImage: result.image, size: result.pointSize)])
            return
        }

        pasteboard.writeObjects([item])
    }

    public static func write(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
