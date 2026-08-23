import AppKit

/// The user-facing half of the updater: three alerts, and the activation dance an accessory app
/// needs before any of them will come to the front.
@MainActor
public enum UpdatePresenter {

    /// A newer release exists.
    ///
    /// "Download" opens the disk image in the browser rather than fetching it in-process. A menu
    /// bar app cannot replace its own bundle while running, so the honest thing is to hand the
    /// download to the browser and let the normal drag-to-Applications flow happen.
    public static func presentAvailable(
        _ release: GitHubRelease,
        current: AppVersion,
        onSkip: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(AppInfo.name) \(release.version.displayString) is available"

        var summary = "You have \(current.displayString)."
        if let asset = release.asset {
            let size = asset.sizeLabel
            summary += size.isEmpty ? " The update is \(asset.name)." : " The update is \(asset.name), \(size)."
        }
        if release.isPrerelease {
            summary += " This is a pre-release."
        }
        alert.informativeText = summary

        if !release.notes.isEmpty {
            alert.accessoryView = notesView(release.notes)
        }

        alert.addButton(withTitle: "Download")        // .alertFirstButtonReturn
        alert.addButton(withTitle: "Later")           // .alertSecondButtonReturn
        alert.addButton(withTitle: "Skip This Version")
        // Esc should mean "not now", not "never mention this again".
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.buttons[2].keyEquivalent = ""

        switch runModal(alert) {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.downloadURL)
        case .alertThirdButtonReturn:
            onSkip()
        default:
            break
        }
    }

    /// The answer to a check the user asked for and that found nothing. Deliberately an alert and
    /// not the HUD: someone who clicked a menu item is waiting for a definite answer, and the HUD
    /// can be switched off.
    public static func presentUpToDate(current: AppVersion) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(AppInfo.name) is up to date"
        alert.informativeText = "You are running version \(current.displayString) (build \(AppInfo.build))."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "All Releases")
        if runModal(alert) == .alertSecondButtonReturn {
            NSWorkspace.shared.open(AppInfo.releasesPageURL)
        }
    }

    public static func presentFailure(_ error: UpdateError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not check for updates"
        alert.informativeText = error.errorDescription ?? "Something went wrong."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Releases Page")
        if runModal(alert) == .alertSecondButtonReturn {
            NSWorkspace.shared.open(AppInfo.releasesPageURL)
        }
    }

    // MARK: - Plumbing

    /// Release notes are Markdown. Rendering them properly is a rabbit hole for a box this size,
    /// so they go in a scrollable, selectable, read-only text view as written.
    private static func notesView(_ notes: String) -> NSView {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 150))
        text.string = notes
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.font = .preferredFont(forTextStyle: .callout)
        text.textContainerInset = NSSize(width: 2, height: 4)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 150))
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .bezelBorder
        return scroll
    }

    /// An accessory app has no Dock presence, so an alert raised from the menu bar can open behind
    /// whatever the user was working in. Lifting the activation policy for the alert's lifetime is
    /// the same trick the settings window uses.
    private static func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previousPolicy) }

        alert.window.orderFrontRegardless()
        return alert.runModal()
    }
}
