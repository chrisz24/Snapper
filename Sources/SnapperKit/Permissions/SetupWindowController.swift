import AppKit
import SwiftUI

/// First-run setup: the two things that stop Snapper working until they are dealt with.
///
/// Both are skippable. Nothing here is required to use the app — Screen Recording can be granted
/// later from the About pane, and the shortcuts can simply be rebound to combinations macOS does
/// not already own.
@MainActor
public final class SetupWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let bindings: HotkeyBindings

    /// Called when setup closes, so shortcuts can be re-registered against the new system state.
    public var onFinish: (() -> Void)?

    public init(settings: SettingsStore, bindings: HotkeyBindings) {
        self.settings = settings
        self.bindings = bindings
        super.init()
    }

    public var debugWindow: NSWindow? { window }

    /// Shows setup only if it has never been seen.
    public func showIfNeeded() {
        guard !settings.hasCompletedSetup else { return }
        show()
    }

    public func show(forcedBlocked: [(GlobalAction, String)]? = nil, openingGuide: Bool = false) {
        if let window {
            focus(window)
            return
        }

        let model = SetupModel(settings: settings, bindings: bindings, forcedBlocked: forcedBlocked,
                               opensGuideImmediately: openingGuide)
        model.onClose = { [weak self] in self?.close() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up \(AppInfo.name)"
        window.contentView = NSHostingView(rootView: SetupView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window
        focus(window)
    }

    public func close() {
        settings.hasCompletedSetup = true
        window?.close()
    }

    private func focus(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        Task { @MainActor in
            for attempt in 0..<4 {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                if window.isKeyWindow { return }
                try? await Task.sleep(for: .milliseconds(60 * (attempt + 1)))
            }
        }
    }

    public func windowWillClose(_ notification: Notification) {
        // Closing by any route counts as having seen it; the menu bar can reopen it on demand.
        settings.hasCompletedSetup = true
        window = nil
        NSApp.setActivationPolicy(.accessory)
        onFinish?()
    }
}

@MainActor
final class SetupModel: ObservableObject {
    @Published var hasScreenRecording: Bool
    @Published var blocked: [(GlobalAction, String)] = []

    let settings: SettingsStore
    let bindings: HotkeyBindings
    var onClose: (() -> Void)?

    private var activationObserver: NSObjectProtocol?
    /// Forces the blocked state, so the interface for it can be inspected on a Mac where the
    /// system shortcuts happen to be switched off.
    private let forcedBlocked: [(GlobalAction, String)]?
    /// Opens the keyboard guide as soon as the window appears, so `--setup-demo … --guide` can
    /// show that sheet without anyone having to click for it.
    let opensGuideImmediately: Bool

    init(settings: SettingsStore, bindings: HotkeyBindings,
         forcedBlocked: [(GlobalAction, String)]? = nil,
         opensGuideImmediately: Bool = false) {
        self.forcedBlocked = forcedBlocked
        self.opensGuideImmediately = opensGuideImmediately
        self.settings = settings
        self.bindings = bindings
        self.hasScreenRecording = PermissionsChecker.hasScreenRecordingAccess
        refresh()

        // Coming back from System Settings is the moment the answer is likely to have changed,
        // so the state refreshes itself rather than waiting to be asked.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    var shortcutsAreClear: Bool { blocked.isEmpty }

    /// The whole Screenshots pane as it currently stands, ordered as System Settings lists it so
    /// the instructions can be read alongside the real thing.
    var screenshotRows: [SystemShortcuts.ScreenshotRow] {
        let rows = SystemShortcuts.screenshotRows(
            for: GlobalAction.allCases.map { bindings.hotkey(for: $0) })
        guard forcedBlocked != nil else { return rows }
        // Same reason the blocked list can be forced: on a Mac where these have already been freed
        // up, there would otherwise be no way to see what this screen looks like with work to do.
        return rows.map {
            SystemShortcuts.ScreenshotRow(id: $0.id, label: $0.label,
                                          blocksSnapper: $0.blocksSnapper,
                                          isEnabled: $0.blocksSnapper ? true : $0.isEnabled)
        }
    }

    /// Re-reads the system's table and reports what it still owns, for the guide's Done check.
    func verifyShortcutsFreed() -> [String] {
        refresh()
        return SystemShortcuts.settingsLabels(toFreeUp: blocked.map { bindings.hotkey(for: $0.0) })
    }

    func refresh() {
        hasScreenRecording = PermissionsChecker.hasScreenRecordingAccess
        blocked = forcedBlocked ?? SystemShortcuts.blockedActions(using: bindings)
    }

    func requestScreenRecording() {
        PermissionsChecker.requestScreenRecordingAccess()
        PermissionsChecker.openScreenRecordingSettings()
    }

    /// Rebinds the capture shortcuts to ⌥⌘ combinations, which macOS does not use.
    func useAlternativeShortcuts() {
        let alternatives: [GlobalAction: Hotkey] = [
            .captureFullScreen: Hotkey(keyCode: 20, modifiers: [.command, .option]),
            .captureRegion: Hotkey(keyCode: 21, modifiers: [.command, .option]),
            .captureWindow: Hotkey(keyCode: 23, modifiers: [.command, .option]),
        ]
        for (action, hotkey) in alternatives {
            bindings.setHotkey(hotkey, for: action)
        }
        refresh()
    }
}
