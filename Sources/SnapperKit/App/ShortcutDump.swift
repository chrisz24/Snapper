import Foundation
import AppKit

/// Prints the effective shortcut for every action, distinguishing a stored override from the
/// shipped default.
///
///     dist/Snapper.app/Contents/MacOS/Snapper --dump-shortcuts
@MainActor
public enum ShortcutDump {

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    public static func run(bindings: HotkeyBindings) -> Int32 {
        print("")
        print("Global")
        for action in GlobalAction.allCases {
            let effective = bindings.hotkey(for: action)
            let note = effective == action.defaultHotkey
                ? "(shipped default)"
                : "(customised; shipped default is \(action.defaultHotkey.displayString))"
            print("  " + pad(action.rawValue, 22) + pad(effective.displayString, 8) + note)
        }

        print("")
        print("Quick actions")
        for action in QuickAction.allCases {
            let effective = bindings.hotkey(for: action)
            let note = effective == action.defaultHotkey
                ? "(shipped default)"
                : "(customised; shipped default is \(action.defaultHotkey.displayString))"
            let enabled = bindings.isEnabled(action) ? "" : "  [disabled]"
            print("  " + pad(action.rawValue, 22) + pad(effective.displayString, 8) + note + enabled)
        }

        print("")
        print("Raw values")
        for action in GlobalAction.allCases {
            let h = bindings.hotkey(for: action)
            print("  " + pad(action.rawValue, 22) + "keyCode=\(h.keyCode) modifiers=\(h.modifierFlagsRawValue)  // \(h.displayString)")
        }
        for action in QuickAction.allCases {
            let h = bindings.hotkey(for: action)
            print("  " + pad(action.rawValue, 22) + "keyCode=\(h.keyCode) modifiers=\(h.modifierFlagsRawValue)  // \(h.displayString)")
        }
        print("")
        fflush(stdout)   // exit() does not flush on its own
        return 0
    }
}
