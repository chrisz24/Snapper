import AppKit

/// The user-facing half of the updater: three alerts, and the activation dance an accessory app
/// needs before any of them will come to the front.
@MainActor
public enum UpdatePresenter {

    /// A newer release exists.
    ///
    /// "Install" downloads the package, verifies it, and hands it to macOS's Installer. Snapper
    /// cannot replace its own bundle directly: a package installs to /Applications, which is owned
    /// by root, so the privileged step has to be done by Installer with the user's consent. What
    /// this flow removes is the trip to a browser and the manual download, not the password prompt.
    ///
    /// A release with no `.pkg` attached falls back to opening the download in a browser.
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

        let canInstall = release.asset?.name.lowercased().hasSuffix(".pkg") == true
        alert.addButton(withTitle: canInstall ? "Install" : "Download")  // .alertFirstButtonReturn
        alert.addButton(withTitle: "Later")                              // .alertSecondButtonReturn
        alert.addButton(withTitle: "Skip This Version")
        // Esc should mean "not now", not "never mention this again".
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.buttons[2].keyEquivalent = ""

        switch runModal(alert) {
        case .alertFirstButtonReturn:
            if canInstall {
                install(release)
            } else {
                NSWorkspace.shared.open(release.downloadURL)
            }
        case .alertThirdButtonReturn:
            onSkip()
        default:
            break
        }
    }

    /// Kept alive for the duration of a download; nothing else owns them.
    private static var installer: UpdateInstaller?
    private static var progressWindow: UpdateProgressWindow?

    private static func install(_ release: GitHubRelease) {
        guard installer == nil else { return }

        let installer = UpdateInstaller()
        let window = UpdateProgressWindow()
        Self.installer = installer
        Self.progressWindow = window

        window.show(title: "Downloading \(AppInfo.name) \(release.version.displayString)")
        window.onCancel = { installer.cancel() }

        // Polling the published value rather than observing it: this file deliberately has no
        // Combine or SwiftUI in it, and the panel only needs to move a few times a second.
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                if let progress = installer.progress { window.update(progress) }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }

        Task { @MainActor in
            let outcome = await installer.fetch(release)
            ticker.cancel()
            window.close()
            Self.installer = nil
            Self.progressWindow = nil

            switch outcome {
            case .success(let package):
                confirmInstall(package, release: release)
            case .failure(.cancelled):
                break
            case .failure(let error):
                presentDownloadFailure(error, release: release)
            }
        }
    }

    /// The package is verified by this point. Snapper stays up while Installer works and relaunches
    /// itself once the bundle on disk has actually been replaced — see `UpdateRelauncher` for why
    /// that is done by watching rather than by quitting and hoping.
    private static func confirmInstall(_ package: URL, release: GitHubRelease) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(AppInfo.name) \(release.version.displayString) is ready to install"
        alert.informativeText = """
            The download is signed by the same developer as this copy and accepted by macOS.

            macOS will ask for your password, as it does for any installer. \(AppInfo.name) reopens \
            itself once the install has finished, and stays as it is if you cancel.
            """
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"

        guard runModal(alert) == .alertFirstButtonReturn else {
            try? FileManager.default.removeItem(at: package)
            return
        }

        NSWorkspace.shared.open(package)
        UpdateRelauncher.relaunchWhenInstalled {
            HUD.shared.show("Update installed — reopening \(AppInfo.name)")
        }
    }

    private static func presentDownloadFailure(_ error: UpdateInstaller.Failure, release: GitHubRelease) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not install the update"
        alert.informativeText = (error.errorDescription ?? "Something went wrong.")
            + "\n\nYou can download it yourself from the release page instead."
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        if runModal(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
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
