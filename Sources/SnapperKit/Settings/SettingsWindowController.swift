import AppKit
import SwiftUI

public enum SettingsTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    case general, capture, text, quickActions, shortcuts, about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .capture: "Capture"
        case .text: "Text Recognition"
        case .quickActions: "Quick Actions"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera"
        case .text: "text.viewfinder"
        case .quickActions: "bolt"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }

    /// Sidebar icon tint, matching the way System Settings colours its rows.
    public var tint: String {
        switch self {
        case .general: "gray"
        case .capture: "blue"
        case .text: "purple"
        case .quickActions: "orange"
        case .shortcuts: "teal"
        case .about: "gray"
        }
    }
}

/// Hosts the settings window.
///
/// An accessory app has no menu bar of its own, so the window is created and fronted by hand and
/// the activation policy is lifted for as long as it is open — otherwise it would appear behind
/// whatever the user was working in.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var tabSelection: SettingsTabSelection?
    private let settings: SettingsStore
    private let bindings: HotkeyBindings
    private let onHotkeysChanged: () -> Void
    private let onRunSetup: () -> Void

    public init(
        settings: SettingsStore,
        bindings: HotkeyBindings,
        onHotkeysChanged: @escaping () -> Void,
        onRunSetup: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.bindings = bindings
        self.onHotkeysChanged = onHotkeysChanged
        self.onRunSetup = onRunSetup
        super.init()
    }

    /// The live settings window. Exposed because `NavigationSplitView` replaces the window title
    /// with the selected section's name, so looking it up by title is unreliable.
    public var debugWindow: NSWindow? { window }

    public func show(tab: SettingsTab = .general) {
        if let window {
            tabSelection?.selection = tab
            focus(window)
            return
        }

        let selection = SettingsTabSelection(selection: tab)
        let view = SettingsView(
            settings: settings,
            bindings: bindings,
            tabSelection: selection,
            onHotkeysChanged: onHotkeysChanged,
            onRunSetup: onRunSetup
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppInfo.name) Settings"
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 660, height: 460)
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        self.window = window
        self.tabSelection = selection
        focus(window)
    }

    /// Bringing an accessory app forward is a two-step affair: the activation policy has to change
    /// *before* the activation request, and the request only takes effect on a later run-loop pass.
    /// Making the window key in the same turn silently leaves it unfocused — and an unfocused
    /// window receives no key events, which would make every shortcut recorder inert.
    private func focus(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)

        // The non-deprecated activate() politely declines when another app owns the front, and
        // even the forceful variant is best-effort — macOS can refuse outright. A window that
        // never becomes key receives no key events, which would leave every shortcut recorder
        // inert, so this retries briefly rather than giving up after one attempt.
        Task { @MainActor in
            for attempt in 0..<4 {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                if window.isKeyWindow { return }
                try? await Task.sleep(for: .milliseconds(60 * (attempt + 1)))
            }
        }
    }

    public func windowWillClose(_ notification: Notification) {
        // Closing the window while a recorder was armed would otherwise leave every shortcut
        // suspended with nothing left on screen to switch them back on.
        HotkeyManager.shared.forceResume()

        // Back to a menu-bar-only app, so no stray Dock icon lingers.
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Lets the menu bar open Settings straight to a chosen tab.
@MainActor
public final class SettingsTabSelection: ObservableObject {
    @Published public var selection: SettingsTab
    public init(selection: SettingsTab) { self.selection = selection }
}
