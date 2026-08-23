import Foundation
import AppKit
import Carbon.HIToolbox

/// Shortcuts that are live for the whole session.
public enum GlobalAction: String, CaseIterable, Codable, Sendable {
    case captureRegion, captureWindow, captureFullScreen, ocrRegion, ocrLastCapture

    public var title: String {
        switch self {
        case .captureRegion: "Capture Selection"
        case .captureWindow: "Capture Window"
        case .captureFullScreen: "Capture Screen"
        case .ocrRegion: "Copy Text from Selection"
        case .ocrLastCapture: "Copy Text from Last Capture"
        }
    }

    /// The three capture shortcuts take over ⌘⇧3, ⌘⇧4 and ⌘⇧5 — the combinations macOS uses for
    /// its own screenshots. That only works where the system's versions have been switched off in
    /// Keyboard Settings — where they are still active, macOS handles them first and Snapper never
    /// sees the keystroke. The Shortcuts pane checks the system's table and says so outright.
    public var defaultHotkey: Hotkey {
        switch self {
        case .captureRegion:     Hotkey(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .shift])
        case .captureWindow:     Hotkey(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift])
        case .captureFullScreen: Hotkey(keyCode: UInt32(kVK_ANSI_3), modifiers: [.command, .shift])
        case .ocrRegion:         Hotkey(keyCode: UInt32(kVK_ANSI_O), modifiers: [.command, .shift])
        case .ocrLastCapture:    Hotkey(keyCode: UInt32(kVK_ANSI_O), modifiers: [.command, .option])
        }
    }
}

/// Actions offered while a capture's preview is on screen.
public enum QuickAction: String, CaseIterable, Codable, Sendable {
    case copyImage, saveAs, saveToDefault, ocr, markup, revealInFinder, openInPreview, delete, dismiss

    public var title: String {
        switch self {
        case .copyImage: "Copy to Clipboard"
        case .saveAs: "Save As…"
        case .saveToDefault: "Save to Default Folder"
        case .ocr: "Copy Text (OCR)"
        case .markup: "Markup…"
        case .revealInFinder: "Reveal in Finder"
        case .openInPreview: "Open in Preview"
        case .delete: "Delete"
        case .dismiss: "Dismiss"
        }
    }

    public var defaultHotkey: Hotkey {
        switch self {
        case .copyImage:     Hotkey(keyCode: UInt32(kVK_ANSI_C), modifiers: [.command])
        case .saveAs:        Hotkey(keyCode: UInt32(kVK_ANSI_S), modifiers: [.command])
        case .saveToDefault: Hotkey(keyCode: UInt32(kVK_ANSI_S), modifiers: [.command, .shift])
        case .ocr:           Hotkey(keyCode: UInt32(kVK_ANSI_O), modifiers: [.command])
        case .markup:        Hotkey(keyCode: UInt32(kVK_ANSI_E), modifiers: [.command])
        case .revealInFinder: Hotkey(keyCode: UInt32(kVK_ANSI_R), modifiers: [.command])
        case .openInPreview: Hotkey(keyCode: UInt32(kVK_Return), modifiers: [.command])
        case .delete:        Hotkey(keyCode: UInt32(kVK_Delete), modifiers: [.command])
        case .dismiss:       Hotkey(keyCode: UInt32(kVK_Escape), modifiers: [.command])
        }
    }

    /// The three shown on the preview itself. Advertising them is what keeps the global key grab
    /// honest — you can see what has been taken over while it is taken over.
    public static let advertised: [QuickAction] = [.copyImage, .saveAs, .delete]

    /// Actions that are pointless once the file is already in its final home.
    public var requiresSavedFile: Bool {
        self == .revealInFinder
    }
}

/// Persists the user's shortcut choices, falling back to the defaults above.
@MainActor
public final class HotkeyBindings: ObservableObject {
    public static let shared = HotkeyBindings()

    private let defaults: UserDefaults
    private static let globalKey = "hotkeys.global"
    private static let quickKey = "hotkeys.quick"
    private static let disabledQuickKey = "hotkeys.quick.disabled"

    @Published private var globalOverrides: [String: Hotkey] = [:]
    @Published private var quickOverrides: [String: Hotkey] = [:]
    @Published private var disabledQuickActions: Set<String> = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        globalOverrides = Self.load(Self.globalKey, from: defaults)
        quickOverrides = Self.load(Self.quickKey, from: defaults)
        disabledQuickActions = Set(defaults.stringArray(forKey: Self.disabledQuickKey) ?? [])
        normalise()
    }

    /// Drops overrides that merely restate the current default, which happens when a default
    /// changes to match what someone had already chosen.
    private func normalise() {
        let globalBefore = globalOverrides.count
        let quickBefore = quickOverrides.count

        globalOverrides = globalOverrides.filter { key, value in
            guard let action = GlobalAction(rawValue: key) else { return false }
            return value != action.defaultHotkey
        }
        quickOverrides = quickOverrides.filter { key, value in
            guard let action = QuickAction(rawValue: key) else { return false }
            return value != action.defaultHotkey
        }

        if globalOverrides.count != globalBefore { Self.save(globalOverrides, Self.globalKey, to: defaults) }
        if quickOverrides.count != quickBefore { Self.save(quickOverrides, Self.quickKey, to: defaults) }
    }

    public func hotkey(for action: GlobalAction) -> Hotkey {
        globalOverrides[action.rawValue] ?? action.defaultHotkey
    }

    public func hotkey(for action: QuickAction) -> Hotkey {
        quickOverrides[action.rawValue] ?? action.defaultHotkey
    }

    public func setHotkey(_ hotkey: Hotkey?, for action: GlobalAction) {
        // Storing a value identical to the default would only leave stale clutter behind, and
        // would stop the binding tracking the default if it ever changes.
        if let hotkey, hotkey != action.defaultHotkey {
            globalOverrides[action.rawValue] = hotkey
        } else {
            globalOverrides.removeValue(forKey: action.rawValue)
        }
        Self.save(globalOverrides, Self.globalKey, to: defaults)
    }

    public func setHotkey(_ hotkey: Hotkey?, for action: QuickAction) {
        if let hotkey, hotkey != action.defaultHotkey {
            quickOverrides[action.rawValue] = hotkey
        } else {
            quickOverrides.removeValue(forKey: action.rawValue)
        }
        Self.save(quickOverrides, Self.quickKey, to: defaults)
    }

    public func isEnabled(_ action: QuickAction) -> Bool {
        !disabledQuickActions.contains(action.rawValue)
    }

    public func setEnabled(_ enabled: Bool, for action: QuickAction) {
        if enabled { disabledQuickActions.remove(action.rawValue) }
        else { disabledQuickActions.insert(action.rawValue) }
        defaults.set(Array(disabledQuickActions), forKey: Self.disabledQuickKey)
    }

    public func resetToDefaults() {
        globalOverrides = [:]
        quickOverrides = [:]
        disabledQuickActions = []
        defaults.removeObject(forKey: Self.globalKey)
        defaults.removeObject(forKey: Self.quickKey)
        defaults.removeObject(forKey: Self.disabledQuickKey)
    }

    /// Any other action already using this combination — surfaced by the recorder as a warning.
    public func conflict(with hotkey: Hotkey, excludingGlobal: GlobalAction? = nil, excludingQuick: QuickAction? = nil) -> String? {
        for action in GlobalAction.allCases where action != excludingGlobal {
            if self.hotkey(for: action) == hotkey { return action.title }
        }
        for action in QuickAction.allCases where action != excludingQuick {
            if self.hotkey(for: action) == hotkey { return action.title }
        }
        return nil
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> [String: Hotkey] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Hotkey].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ value: [String: Hotkey], _ key: String, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
