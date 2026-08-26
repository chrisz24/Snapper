import Foundation
import AppKit

/// Puts a preview on screen and holds it, so its appearance can be inspected and screenshotted.
///
///     dist/Snapper.app/Contents/MacOS/Snapper --preview-demo [seconds]
@MainActor
public enum PreviewDemo {

    private static func dump(view: NSView?, depth: Int) {
        guard let view, depth < 5 else { return }
        let pad = String(repeating: "  ", count: depth)
        let layer = view.layer
        var bits: [String] = ["\(type(of: view))"]
        if let layer {
            bits.append("radius=\(layer.cornerRadius)")
            if let bg = layer.backgroundColor { bits.append("bg=\(bg.alpha > 0 ? "opaque-ish" : "clear")") }
            if layer.shadowOpacity > 0 { bits.append("shadowOpacity=\(layer.shadowOpacity)") }
            if layer.masksToBounds { bits.append("masks") }
            if !layer.sublayers.isNilOrEmpty { bits.append("sublayers=\(layer.sublayers?.count ?? 0)") }
        }
        print("  VIEW \(pad)\(bits.joined(separator: " "))")
        for sub in view.subviews { dump(view: sub, depth: depth + 1) }
    }

    public static func run(settings: SettingsStore, seconds: Double,
                           portrait: Bool = false) async -> Int32 {
        settings.previewDuration = 0        // hold until dismissed
        settings.showPreview = true
        settings.previewCorner = .bottomRight

        // Park the pointer on the least cluttered display so the capture shows the panel's own
        // chrome rather than whatever happens to be behind it.
        let originalPointer = NSEvent.mouseLocation
        if let target = NSScreen.screens.last, NSScreen.screens.count > 1 {
            let main = NSScreen.screens[0]
            CGWarpMouseCursorPosition(CGPoint(x: target.frame.midX, y: main.frame.maxY - target.frame.midY))
            CGAssociateMouseAndMouseCursorPosition(1)
            try? await Task.sleep(for: .milliseconds(200))
        }
        defer {
            let main = NSScreen.screens[0]
            CGWarpMouseCursorPosition(CGPoint(x: originalPointer.x, y: main.frame.maxY - originalPointer.y))
            CGAssociateMouseAndMouseCursorPosition(1)
        }

        // A tall capture is the awkward case: the thumbnail is sized to fit its longest edge, so a
        // portrait shot leaves the panel far narrower than the row of shortcut hints beneath it.
        let page = portrait ? CGSize(width: 380, height: 860) : CGSize(width: 420, height: 280)
        guard let image = OCRSelfTest.renderPage(width: page.width, height: page.height)
        else { return 1 }
        let url = AppInfo.scratchDirectory.appendingPathComponent("preview-demo.png")
        try? ImageWriter.pngData(image, scale: 2)?.write(to: url)

        let result = CaptureResult(fileURL: url, image: image, scale: 2, mode: .region, isTemporary: true)
        let preview = PreviewController(settings: settings)
        preview.show(result)

        try? await Task.sleep(for: .milliseconds(600))

        guard let frame = preview.debugPanelFrame, let screen = preview.debugTargetScreen else { return 1 }

        // screencapture -R measures from the top-left of the main display; AppKit from the
        // bottom-left. Pad the rect so the panel's own shadow is included in the grab.
        let mainMaxY = NSScreen.screens[0].frame.maxY
        let pad: CGFloat = 14
        let x = frame.minX - pad
        let y = mainMaxY - frame.maxY - pad
        let w = frame.width + pad * 2
        let h = frame.height + pad * 2

        print("PANEL \(Int(frame.width))x\(Int(frame.height)) on screen \(Int(screen.frame.width))x\(Int(screen.frame.height))")

        if let panel = NSApp.windows.first(where: { $0 is PreviewPanel }) {
            print("WINDOW hasShadow=\(panel.hasShadow) opaque=\(panel.isOpaque) "
                  + "bg=\(panel.backgroundColor.description) "
                  + "frameViewClass=\(type(of: panel.contentView?.superview as Any))")
            dump(view: panel.contentView?.superview, depth: 0)
        }
        print("RECT \(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))")
        fflush(stdout)

        try? await Task.sleep(for: .seconds(seconds))
        preview.dismiss(animated: false)
        return 0
    }
}

private extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
