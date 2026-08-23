import Foundation
import AppKit

/// Drives the preview and quick-action layers against a synthesised capture.
///
/// Needs no Screen Recording permission, so placement, the countdown, the system-wide key grab,
/// and auto-dismissal can all be asserted rather than eyeballed. Run with:
///
///     dist/Snapper.app/Contents/MacOS/Snapper --preview-test
@MainActor
public enum PreviewSelfTest {

    /// Core Graphics measures from the top-left of the main display, AppKit from its bottom-left.
    private static func warpPointer(to appKitPoint: CGPoint) {
        guard let main = NSScreen.screens.first else { return }
        let flipped = CGPoint(x: appKitPoint.x, y: main.frame.maxY - appKitPoint.y)
        CGWarpMouseCursorPosition(flipped)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    public static func run(settings: SettingsStore) async -> Int32 {
        var failures = 0

        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            let mark = passed ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
            print("  \(mark) \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            if !passed { failures += 1 }
        }

        print("\n\u{001B}[1mPreview & quick-action self-test\u{001B}[0m")

        settings.previewCorner = .bottomRight
        settings.previewDuration = 2.5
        settings.showPreview = true
        settings.quickActionActivation = .global

        guard let image = OCRSelfTest.renderPage(width: 400, height: 260) else {
            check("render a stand-in capture", false)
            return 1
        }

        let url = AppInfo.scratchDirectory.appendingPathComponent("preview-test.png")
        guard let data = ImageWriter.pngData(image, scale: 2) else {
            check("encode the stand-in capture", false)
            return 1
        }
        try? data.write(to: url)

        let result = CaptureResult(fileURL: url, image: image, scale: 2, mode: .region, isTemporary: true)
        check("built a stand-in capture", true, "\(image.width)×\(image.height) px @2×")

        print("    pointer: \(NSEvent.mouseLocation)")
        for (i, screen) in NSScreen.screens.enumerated() {
            print("    screen \(i): frame=\(screen.frame) visible=\(screen.visibleFrame)"
                  + (screen == DisplayLocator.screenUnderPointer ? "  ← under pointer" : ""))
        }

        // ---- Clipboard shape -------------------------------------------------------------------
        // Writing the image and the file URL as two separate pasteboard items made apps that paste
        // the whole board insert the picture twice.
        ClipboardWriter.write(result)
        let board = NSPasteboard.general
        let itemCount = board.pasteboardItems?.count ?? 0
        check("clipboard holds exactly one item", itemCount == 1,
              "\(itemCount) item(s) — more than one pastes the picture repeatedly")

        let types = board.pasteboardItems?.first?.types.map(\.rawValue) ?? []
        check("that item carries PNG", types.contains(NSPasteboard.PasteboardType.png.rawValue))
        check("that item carries TIFF", types.contains(NSPasteboard.PasteboardType.tiff.rawValue))
        check("that item carries the file URL", types.contains(NSPasteboard.PasteboardType.fileURL.rawValue))

        let images = board.readObjects(forClasses: [NSImage.self], options: nil) ?? []
        check("a pasting app sees a single image", images.count == 1, "\(images.count) found")

        let urls = board.readObjects(forClasses: [NSURL.self], options: nil) ?? []
        check("and a single file reference", urls.count == 1, "\(urls.count) found")
        // -----------------------------------------------------------------------------------------

        let preview = PreviewController(settings: settings)
        var firedAction: QuickAction?
        preview.onAction = { action, _ in firedAction = action }

        preview.show(result)
        try? await Task.sleep(for: .milliseconds(400))

        check("preview is on screen", preview.isShowing)
        check("quick-action keys are grabbed system-wide", preview.debugKeysGrabbed,
              "⌘C / ⌘S are ours for \(settings.previewDuration)s")

        // Placement: bottom-right of the *visible* frame, which already excludes Dock and menu bar.
        if let frame = preview.debugPanelFrame, let screen = preview.debugTargetScreen {
            let visible = screen.visibleFrame
            let rightInset = visible.maxX - frame.maxX
            let bottomInset = frame.minY - visible.minY
            check("anchored to the bottom-right corner",
                  abs(rightInset - 16) <= 1.5 && abs(bottomInset - 16) <= 1.5,
                  "insets right=\(Int(rightInset)) bottom=\(Int(bottomInset))")
            check("sits inside the visible frame (clear of the Dock)",
                  visible.contains(frame),
                  "panel \(Int(frame.width))×\(Int(frame.height))")
        } else {
            check("panel has a frame", false)
        }

        // Right-click menu
        if let menu = preview.debugContextMenu() {
            let titles = menu.items.map(\.title)
            check("right-click menu is offered", menu.items.count > 3, "\(menu.items.count) items")
            check("menu leads with Copy", titles.first == QuickAction.copyImage.title, titles.first ?? "none")
            check("menu offers the text grab", titles.contains(QuickAction.ocr.title))
            check("menu offers Save As", titles.contains(QuickAction.saveAs.title))
            check("menu offers Delete", titles.contains(QuickAction.delete.title))
            check("menu shows the matching shortcuts",
                  menu.items.first(where: { $0.title == QuickAction.copyImage.title })?.keyEquivalent == "c",
                  "⌘C rendered on the Copy item")
            // Reveal in Finder is meaningless for a capture that has no permanent home yet.
            check("Reveal is withheld while the file is still temporary",
                  !titles.contains(QuickAction.revealInFinder.title))
        } else {
            check("right-click menu is offered", false, "no menu built")
        }

        let earlyProgress = preview.debugProgress
        try? await Task.sleep(for: .milliseconds(900))
        let laterProgress = preview.debugProgress
        check("countdown is running", laterProgress < earlyProgress,
              String(format: "%.2f → %.2f", earlyProgress, laterProgress))

        // Let it expire on its own.
        try? await Task.sleep(for: .milliseconds(2200))
        check("auto-dismissed at the deadline", !preview.isShowing)
        check("keys handed back after dismissal", !preview.debugKeysGrabbed,
              "⌘C belongs to the frontmost app again")
        check("no action fired on its own", firedAction == nil)

        // "Until dismissed" should hold the preview open indefinitely.
        settings.previewDuration = 0
        preview.show(result)
        try? await Task.sleep(for: .milliseconds(1200))
        check("a zero duration keeps the preview up", preview.isShowing)
        preview.dismiss(animated: false)
        check("explicit dismissal releases the keys", !preview.debugKeysGrabbed)

        // Multi-display: put the pointer on each screen in turn and confirm the preview follows.
        if NSScreen.screens.count > 1 {
            let originalPointer = NSEvent.mouseLocation
            settings.previewDuration = 0

            for (index, screen) in NSScreen.screens.enumerated() {
                warpPointer(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
                try? await Task.sleep(for: .milliseconds(250))

                preview.show(result)
                try? await Task.sleep(for: .milliseconds(400))

                let landed = preview.debugTargetScreen == screen
                let inside = preview.debugPanelFrame.map { screen.visibleFrame.contains($0) } ?? false
                check("preview lands on display \(index)", landed && inside,
                      "origin x=\(Int(screen.frame.minX))")
                preview.dismiss(animated: false)
            }

            warpPointer(to: originalPointer)
            check("pointer restored", true)
        } else {
            print("  \u{001B}[2m·\u{001B}[0m only one display attached; multi-display check skipped")
        }

        try? FileManager.default.removeItem(at: url)

        print("")
        if failures == 0 {
            print("\u{001B}[32mpreview self-test passed\u{001B}[0m\n")
        } else {
            print("\u{001B}[31m\(failures) check(s) failed\u{001B}[0m\n")
        }
        return failures == 0 ? 0 : 1
    }
}
