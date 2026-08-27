import AppKit

/// Reports why the menu bar icon is or is not there, for `--menu-bar-status`.
///
/// Worth having because the two reasons look identical from the outside. Either Snapper never put
/// an icon up — the setting is off — or it did and macOS has no room for it, which is common once
/// enough apps live in the menu bar and certain on a notched display. Guessing between those from
/// an empty menu bar is not possible, so this asks each question separately.
@MainActor
public enum MenuBarStatus {

    public static func report(settings: SettingsStore) -> String {
        let probe = probeStatusItem()
        var lines = [
            "",
            "\u{001B}[1mMenu bar icon\u{001B}[0m",
            "  setting:      \(settings.showMenuBarIcon ? "shown" : "hidden")",
            "  can be added: \(probe.created ? "yes" : "no")",
            "  menu bar:     \(Int(NSStatusBar.system.thickness)) pt thick",
        ]
        if let width = probe.width {
            lines.append("  item width:   \(Int(width)) pt")
        }
        lines.append("")

        if !settings.showMenuBarIcon {
            lines.append("  The icon is switched off in Settings › General › Menu bar.")
            lines.append("  Open \(AppInfo.name) from the Applications folder to reach Settings.")
        } else if probe.created {
            lines.append("  \(AppInfo.name) is adding an icon. If you cannot see one, macOS has run")
            lines.append("  out of menu bar room and dropped it — a notch makes this likely. Quit a")
            lines.append("  few other menu bar apps to check, and note that opening \(AppInfo.name)")
            lines.append("  from the Applications folder still brings up Settings either way.")
        } else {
            lines.append("  macOS refused the icon outright, which is not a setting — something is")
            lines.append("  wrong with this install rather than with the menu bar.")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Adds a real status item, notes whether AppKit accepted it, and takes it straight back out.
    private static func probeStatusItem() -> (created: Bool, width: CGFloat?) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                     accessibilityDescription: AppInfo.name)
        // A button with a window of its own is what "made it into the menu bar" actually means.
        let created = item.button?.window != nil
        let width = item.button?.window?.frame.width
        NSStatusBar.system.removeStatusItem(item)
        return (created, width)
    }
}
