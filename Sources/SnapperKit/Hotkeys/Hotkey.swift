import Foundation
import AppKit
import Carbon.HIToolbox

/// A key combination, stored independently of any windowing framework so it can round-trip
/// through UserDefaults.
public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    /// Virtual key code (kVK_*).
    public var keyCode: UInt32
    /// Raw value of `NSEvent.ModifierFlags`, masked to the device-independent flags.
    public var modifierFlagsRawValue: UInt

    public init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    public var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue).intersection(.deviceIndependentFlagsMask)
    }

    /// Carbon modifier mask for `RegisterEventHotKey`.
    public var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        let m = modifiers
        if m.contains(.command) { result |= UInt32(cmdKey) }
        if m.contains(.shift) { result |= UInt32(shiftKey) }
        if m.contains(.option) { result |= UInt32(optionKey) }
        if m.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    /// Human-readable form in the conventional macOS order: ⌃⌥⇧⌘key.
    public var displayString: String {
        var s = ""
        let m = modifiers
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        s += Self.keyName(for: keyCode)
        return s
    }

    /// Combinations macOS reserves or that would be actively hostile to steal.
    public var isLikelyReserved: Bool {
        let m = modifiers
        // Cmd-Q / Cmd-Tab / Cmd-Space and bare keys with no modifier at all.
        if m.isEmpty { return true }
        if m == [.command] && keyCode == UInt32(kVK_Tab) { return true }
        if m == [.command] && keyCode == UInt32(kVK_Space) { return true }
        return false
    }

    private static let names: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Grave): "`",
    ]

    public static func keyName(for keyCode: UInt32) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    /// The `NSMenuItem.keyEquivalent` form, so a menu renders the same shortcut the hotkey uses.
    public var keyEquivalentString: String {
        switch keyCode {
        case UInt32(kVK_Return): return "\r"
        case UInt32(kVK_Delete): return "\u{8}"
        case UInt32(kVK_ForwardDelete): return "\u{7F}"
        case UInt32(kVK_Escape): return "\u{1B}"
        case UInt32(kVK_Space): return " "
        case UInt32(kVK_Tab): return "\t"
        default:
            let name = Self.keyName(for: keyCode)
            return name.count == 1 ? name.lowercased() : ""
        }
    }
}
