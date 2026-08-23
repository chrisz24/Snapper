import AppKit
import SwiftUI

/// Shows the thumbnail, runs its countdown, and owns the quick-action session that goes with it.
@MainActor
public final class PreviewController: NSObject, NSMenuDelegate {
    private let settings: SettingsStore
    private let bindings: HotkeyBindings

    private var panel: PreviewPanel?
    private var model: PreviewModel?
    private var session: QuickActionSession?
    private var ticker: Timer?
    private var remaining: TimeInterval = 0
    private var total: TimeInterval = 0
    private var currentResult: CaptureResult?
    /// The screen chosen when the preview was shown. Remembered rather than re-queried, so a
    /// pointer that wanders afterwards cannot move the goalposts.
    private var targetScreen: NSScreen?

    /// A quick action fired for the capture currently on screen.
    public var onAction: ((QuickAction, CaptureResult) -> Void)?
    /// The thumbnail was clicked.
    public var onOpen: ((CaptureResult) -> Void)?

    private let inset: CGFloat = 16

    public init(settings: SettingsStore, bindings: HotkeyBindings? = nil) {
        self.settings = settings
        self.bindings = bindings ?? .shared
        super.init()
    }

    public var isShowing: Bool { panel != nil }

    /// Test hooks, so the panel's placement and key grab can be asserted rather than eyeballed.
    public var debugPanelFrame: NSRect? { panel?.frame }
    public var debugTargetScreen: NSScreen? { targetScreen }
    public var debugKeysGrabbed: Bool { session?.keysAreGrabbed ?? false }
    public var debugProgress: Double { model?.progress ?? -1 }

    /// Test hook: the right-click menu as the panel would present it.
    public func debugContextMenu() -> NSMenu? { buildContextMenu() }

    // MARK: - Presentation

    public func show(_ result: CaptureResult) {
        // A new capture supersedes whatever was on screen, releasing its keys first.
        dismiss(animated: false)

        guard settings.showPreview else {
            // Even with the thumbnail off, the quick-action window should still apply.
            startSession(for: result)
            scheduleExpiry()
            return
        }

        let thumbnailSize = self.thumbnailSize(for: result)
        let model = PreviewModel(image: NSImage(cgImage: result.image, size: result.pointSize))
        model.isTextCapture = result.mode.isForOCR
        model.showsCountdown = settings.previewDuration > 0
        model.hints = hints()
        model.dragURL = result.fileURL
        model.onClick = { [weak self] in
            guard let self, let current = self.currentResult else { return }
            self.onOpen?(current)
            self.dismiss()
        }
        model.onHoverChange = { [weak self] hovering in
            self?.handleHover(hovering)
        }
        model.onClose = { [weak self] in
            self?.dismiss()
        }

        let hosting = PreviewHostingView(
            rootView: PreviewView(model: model, thumbnailSize: thumbnailSize)
        )
        hosting.menuBuilder = { [weak self] in self?.buildContextMenu() }

        // Measured from the view rather than recomputed here. Keeping a second copy of the
        // padding and row heights in the controller meant a tweak to the layout silently pushed
        // the panel off its corner by the difference.
        hosting.layoutSubtreeIfNeeded()
        let contentSize = hosting.fittingSize

        let panel = PreviewPanel(size: contentSize)
        panel.contentView = hosting
        panel.setContentSize(contentSize)

        let panelSize = panel.frame.size
        let destination = origin(for: panelSize)
        // Slide in from just outside the resting position, matching the system's own preview.
        let entryOffset: CGFloat = settings.previewCorner == .bottomLeft || settings.previewCorner == .topLeft ? -40 : 40
        panel.setFrameOrigin(NSPoint(x: destination.x + entryOffset, y: destination.y))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            // setFrame, not setFrameOrigin: NSWindow's animator proxy only animates the former,
            // and the latter silently leaves the window at its entry offset.
            panel.animator().setFrame(NSRect(origin: destination, size: panelSize), display: true)
        }

        self.panel = panel
        self.model = model
        self.currentResult = result

        startSession(for: result)
        scheduleExpiry()
    }

    public func dismiss(animated: Bool = true) {
        ticker?.invalidate()
        ticker = nil
        session?.invalidate()
        session = nil
        currentResult = nil

        guard let panel else {
            model = nil
            return
        }
        self.panel = nil
        self.model = nil

        guard animated else {
            panel.orderOut(nil)
            return
        }

        let exitOffset: CGFloat = settings.previewCorner == .bottomLeft || settings.previewCorner == .topLeft ? -30 : 30
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(
                panel.frame.offsetBy(dx: exitOffset, dy: 0),
                display: true
            )
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    /// Keeps the on-screen thumbnail in step after an action rewrites the file.
    public func update(with result: CaptureResult) {
        currentResult = result
        model?.dragURL = result.fileURL
    }

    // MARK: - Quick actions

    private func startSession(for result: CaptureResult) {
        let session = QuickActionSession(result: result, bindings: bindings)
        session.onAction = { [weak self] action in
            guard let self, let current = self.currentResult else { return }
            self.onAction?(action, current)
        }
        self.session = session

        switch settings.quickActionActivation {
        case .global:
            session.grabKeys()
            if settings.releaseOnAppSwitch {
                session.releaseOnAppSwitch()
            }
        case .hoverOnly:
            break // grabbed on hover instead
        }
    }

    /// A menu that is open counts as the user deciding, so the clock must not run out underneath
    /// them — the same reasoning as pausing on hover. Without this the preview could vanish
    /// mid-menu and take the menu's target with it.
    public func menuWillOpen(_ menu: NSMenu) {
        ticker?.invalidate()
        ticker = nil
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard panel != nil, remaining > 0, settings.previewDuration > 0 else { return }
        startTicker()
    }

    private func handleHover(_ hovering: Bool) {
        // Hovering means the user is still deciding — stop the clock rather than yanking the
        // thumbnail out from under the pointer.
        if hovering {
            ticker?.invalidate()
            ticker = nil
        } else if remaining > 0, settings.previewDuration > 0 {
            startTicker()
        }

        if settings.quickActionActivation == .hoverOnly {
            hovering ? session?.grabKeys() : session?.releaseKeys()
        }
    }

    // MARK: - Right-click menu

    /// Everything the quick-action shortcuts can do, reachable without remembering any of them.
    private func buildContextMenu() -> NSMenu? {
        guard let result = currentResult else { return nil }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let primary: [QuickAction] = [.copyImage, .ocr, .saveAs, .saveToDefault,
                                      .markup, .openInPreview, .revealInFinder]
        for action in primary {
            guard bindings.isEnabled(action) else { continue }
            if action.requiresSavedFile && result.isTemporary { continue }
            menu.addItem(item(for: action))
        }

        menu.addItem(.separator())
        menu.addItem(item(for: .delete))
        menu.addItem(item(for: .dismiss))
        return menu
    }

    private func item(for action: QuickAction) -> NSMenuItem {
        let hotkey = bindings.hotkey(for: action)
        let menuItem = NSMenuItem(
            title: action.title,
            action: #selector(contextMenuItemSelected(_:)),
            keyEquivalent: hotkey.keyEquivalentString
        )
        menuItem.keyEquivalentModifierMask = hotkey.modifiers
        menuItem.target = self
        menuItem.representedObject = action.rawValue
        menuItem.isEnabled = true
        return menuItem
    }

    @objc private func contextMenuItemSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = QuickAction(rawValue: raw),
              let result = currentResult
        else { return }

        // Dismiss first, so the preview gets out of the way the moment a choice is made rather
        // than lingering behind whatever the action opens.
        dismiss()

        guard action != .dismiss else { return }
        onAction?(action, result)
    }

    // MARK: - Countdown

    private func scheduleExpiry() {
        total = settings.previewDuration
        remaining = total
        model?.progress = 1

        guard total > 0 else {
            model?.showsCountdown = false
            return // "until dismissed"
        }
        startTicker()
    }

    private func startTicker() {
        ticker?.invalidate()
        let interval: TimeInterval = 1.0 / 30
        ticker = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remaining -= interval
                self.model?.progress = self.total > 0 ? max(0, self.remaining / self.total) : 0
                if self.remaining <= 0 {
                    self.dismiss()
                }
            }
        }
        // Keep counting while menus or resize loops are running.
        if let ticker { RunLoop.main.add(ticker, forMode: .common) }
    }

    // MARK: - Geometry

    private func hints() -> [PreviewModel.Hint] {
        QuickAction.advertised.compactMap { action in
            guard bindings.isEnabled(action) else { return nil }
            let label: String = switch action {
            case .copyImage: "Copy"
            case .saveAs: "Save"
            case .delete: "Delete"
            default: action.title
            }
            return PreviewModel.Hint(shortcut: bindings.hotkey(for: action).displayString, label: label)
        }
    }

    private func thumbnailSize(for result: CaptureResult) -> CGSize {
        let maxEdge = max(120, settings.previewSize)
        let size = result.pointSize
        guard size.width > 0, size.height > 0 else {
            return CGSize(width: maxEdge, height: maxEdge * 0.66)
        }
        let scale = min(maxEdge / size.width, maxEdge / size.height, 1)
        // Very large captures shrink to fit; small ones are never blown up past their real size.
        let effective = scale == 1 ? min(1, maxEdge / max(size.width, size.height)) : scale
        return CGSize(
            width: max(64, (size.width * effective).rounded()),
            height: max(48, (size.height * effective).rounded())
        )
    }

    private func origin(for size: NSSize) -> NSPoint {
        // visibleFrame already excludes the menu bar and the Dock, wherever the user keeps them.
        guard let screen = DisplayLocator.screenUnderPointer ?? NSScreen.main else {
            return NSPoint(x: 100, y: 100)
        }
        targetScreen = screen
        let frame = screen.visibleFrame

        switch settings.previewCorner {
        case .bottomRight:
            return NSPoint(x: frame.maxX - size.width - inset, y: frame.minY + inset)
        case .bottomLeft:
            return NSPoint(x: frame.minX + inset, y: frame.minY + inset)
        case .topRight:
            return NSPoint(x: frame.maxX - size.width - inset, y: frame.maxY - size.height - inset)
        case .topLeft:
            return NSPoint(x: frame.minX + inset, y: frame.maxY - size.height - inset)
        }
    }
}
