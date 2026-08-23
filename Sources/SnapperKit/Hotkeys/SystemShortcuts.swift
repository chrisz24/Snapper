import Foundation
import AppKit
import Carbon.HIToolbox

/// Detects collisions with macOS's own keyboard shortcuts.
///
/// This matters because `RegisterEventHotKey` happily *accepts* a combination the system already
/// owns — it just never fires, because macOS handles it first. A user can record ⌘⇧4, see it
/// sitting in Settings looking perfectly fine, and be baffled when nothing happens. The only way
/// to warn them is to read the system's own shortcut table.
///
/// The table is only half the story: macOS writes an entry only once a shortcut has been *changed*
/// from its default, so a combination missing from the table is still live at its default setting.
/// Both cases have to be handled, or the warning is wrong in one direction or the other.
public enum SystemShortcuts {

    private static let names: [Int: String] = [
        28: "Screenshot (save screen to file)",
        29: "Screenshot (copy screen)",
        30: "Screenshot (save selection to file)",
        31: "Screenshot (copy selection)",
        184: "Screenshot and recording options",
        32: "Mission Control",
        33: "Mission Control (windows)",
        36: "Application windows",
        60: "Select the previous input source",
        61: "Select the next input source",
        64: "Spotlight search",
        65: "Spotlight Finder window",
        79: "Move left a space",
        81: "Move right a space",
        160: "Launchpad",
        162: "Show Notification Centre",
    ]

    /// The label System Settings prints beside each Screenshots checkbox. Kept apart from `names`:
    /// those read as descriptions inside Snapper, whereas these have to match Apple's wording
    /// exactly, or they are no use to someone scanning that pane for the row to switch off.
    private static let settingsLabels: [Int: String] = [
        28: "Save picture of screen as a file",
        29: "Copy picture of screen to the clipboard",
        30: "Save picture of selected area as a file",
        31: "Copy picture of selected area to the clipboard",
        184: "Screenshot and recording options",
    ]

    /// The order System Settings lists those rows in, so instructions can be followed top to bottom.
    private static let screenshotPaneOrder = [28, 29, 30, 31, 184]

    /// Combinations macOS ships with, mapped to their symbolic-hotkey id. Used when the table has
    /// no entry for a shortcut, which means it is untouched and therefore still active.
    private static var shippedDefaults: [(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, id: Int)] {
        [
            (UInt32(kVK_ANSI_3), [.shift, .command], 28),
            (UInt32(kVK_ANSI_3), [.control, .shift, .command], 29),
            (UInt32(kVK_ANSI_4), [.shift, .command], 30),
            (UInt32(kVK_ANSI_4), [.control, .shift, .command], 31),
            (UInt32(kVK_ANSI_5), [.shift, .command], 184),
            (UInt32(kVK_Space), [.command], 64),
        ]
    }

    /// Only the four modifiers the system table records.
    private static let relevant: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    /// Describes the system shortcut this combination collides with, or nil when it is free.
    public static func conflict(with hotkey: Hotkey) -> String? {
        conflictingID(with: hotkey).map { names[$0] ?? "a macOS system shortcut" }
    }

    /// The Screenshots rows that would have to be switched off for these combinations to reach
    /// Snapper, ordered as System Settings lists them. Combinations owned by something outside
    /// that pane are left out, having no row there to switch off.
    public static func settingsLabels(toFreeUp hotkeys: [Hotkey]) -> [String] {
        let owned = Set(hotkeys.compactMap { conflictingID(with: $0) })
        return screenshotPaneOrder.filter(owned.contains).compactMap { settingsLabels[$0] }
    }

    /// One row of the Screenshots pane, as it currently stands.
    public struct ScreenshotRow: Identifiable, Sendable {
        public let id: Int
        public let label: String
        /// A Snapper shortcut is sitting behind this row, so it is one to switch off.
        public let blocksSnapper: Bool
        /// Whether macOS still has it switched on.
        public let isEnabled: Bool
    }

    /// Every row of the Screenshots pane in the order it appears there, so instructions can mirror
    /// what someone is actually looking at. Showing the whole pane matters: the rows Snapper does
    /// not want are the ones most easily switched off by mistake, and saying "leave these" is more
    /// use than omitting them and leaving it to guesswork.
    public static func screenshotRows(for hotkeys: [Hotkey]) -> [ScreenshotRow] {
        var needed = Set<Int>()
        for hotkey in hotkeys {
            if let id = conflictingID(with: hotkey) {
                needed.insert(id)
            } else if let shipped = shippedDefaults.first(where: {
                $0.keyCode == hotkey.keyCode
                    && $0.modifiers.rawValue == hotkey.modifiers.intersection(relevant).rawValue
            }) {
                // No live collision, but this is still the row that pairs with the combination —
                // kept so an already-freed row shows as done rather than dropping off the list.
                needed.insert(shipped.id)
            }
        }

        return screenshotPaneOrder.compactMap { id in
            guard let label = settingsLabels[id] else { return nil }
            return ScreenshotRow(id: id, label: label,
                                 blocksSnapper: needed.contains(id),
                                 isEnabled: conflictExists(forSymbolicID: id))
        }
    }

    /// The symbolic-hotkey id macOS would intercept this combination with, or nil when it is free.
    private static func conflictingID(with hotkey: Hotkey) -> Int? {
        let wanted = hotkey.modifiers.intersection(relevant).rawValue

        guard let table = readTable() else {
            // Unreadable: fall back to assuming the shipped defaults are in force.
            return shippedDefaults
                .first { $0.keyCode == hotkey.keyCode && $0.modifiers.rawValue == wanted }?.id
        }

        // An entry that is present and switched on genuinely owns the combination.
        for (key, raw) in table {
            guard let id = Int(key),
                  let entry = raw as? [String: Any],
                  (entry["enabled"] as? Bool) == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Any],
                  parameters.count >= 3,
                  let keyCode = (parameters[1] as? NSNumber)?.intValue, keyCode >= 0,
                  let modifiers = (parameters[2] as? NSNumber)?.uintValue
            else { continue }

            guard UInt32(keyCode) == hotkey.keyCode,
                  NSEvent.ModifierFlags(rawValue: modifiers).intersection(relevant).rawValue == wanted
            else { continue }

            return id
        }

        // Absent from the table means never customised, so a shipped default is still active.
        // An entry that is present but switched off means the user freed it up — no conflict.
        if let shipped = shippedDefaults.first(where: {
            $0.keyCode == hotkey.keyCode && $0.modifiers.rawValue == wanted
        }), table[String(shipped.id)] == nil {
            return shipped.id
        }

        return nil
    }

    private static func readTable() -> [String: Any]? {
        // System Settings writes this domain from another process. Without synchronising first, a
        // cached copy can still say "enabled" moments after someone switched a shortcut off, which
        // would make the Done check report a failure that has already been fixed.
        CFPreferencesAppSynchronize(domain as CFString)
        return UserDefaults(suiteName: domain)?.dictionary(forKey: "AppleSymbolicHotKeys")
    }

    private static let domain = "com.apple.symbolichotkeys"

    /// Whether macOS's built-in screenshot shortcuts are currently active, so the interface can
    /// say something true rather than assuming.
    public static var screenshotShortcutsEnabled: Bool {
        [28, 29, 30, 31, 184].contains { conflictExists(forSymbolicID: $0) }
    }

    /// Which of Snapper's own global shortcuts macOS would currently intercept.
    @MainActor
    public static func blockedActions(using bindings: HotkeyBindings) -> [(GlobalAction, String)] {
        GlobalAction.allCases.compactMap { action in
            guard let owner = conflict(with: bindings.hotkey(for: action)) else { return nil }
            return (action, owner)
        }
    }

    private static func conflictExists(forSymbolicID id: Int) -> Bool {
        guard let table = readTable() else { return true }
        guard let entry = table[String(id)] as? [String: Any] else { return true } // untouched default
        return (entry["enabled"] as? Bool) == true
    }
}
