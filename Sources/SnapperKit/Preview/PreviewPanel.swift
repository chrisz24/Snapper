import SwiftUI
import AppKit

/// Floating thumbnail window.
///
/// Never becomes key or main: taking focus from whatever the user is doing would defeat the point
/// of a preview that appears while they carry on working. Keyboard access happens through the
/// session's Carbon hotkeys instead.
final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        // Left off deliberately. On macOS 26 a borderless panel with a system shadow picks up the
        // Liquid Glass backing, which wraps the thumbnail in a heavy rounded halo. The view draws
        // its own restrained shadow instead.
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }
}


/// Hosting view that supplies the preview's right-click menu.
///
/// Implemented in AppKit rather than SwiftUI's `.contextMenu`, because the panel is deliberately
/// non-activating and never becomes key — conditions SwiftUI's context menu does not reliably
/// survive, while `menu(for:)` is exactly the AppKit hook for the job.
final class PreviewHostingView<Content: SwiftUI.View>: NSHostingView<Content> {
    var menuBuilder: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?() ?? super.menu(for: event)
    }
}
