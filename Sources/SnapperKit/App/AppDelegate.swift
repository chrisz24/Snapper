import AppKit
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let settings = SettingsStore.shared
    private let bindings = HotkeyBindings.shared

    private lazy var coordinator = CaptureCoordinator(settings: settings)
    private lazy var preview = PreviewController(settings: settings, bindings: bindings)
    private lazy var runner = QuickActionRunner(settings: settings)
    private lazy var ocr = OCRService(settings: settings)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        bindings: bindings,
        onHotkeysChanged: { [weak self] in self?.registerGlobalHotkeys() },
        onRunSetup: { [weak self] in self?.setup.show() }
    )
    private let reviewPanel = OCRReviewPanel()
    private lazy var setup = SetupWindowController(settings: settings, bindings: bindings)
    private let history = CaptureStore.shared
    private lazy var markup = MarkupWindowController(settings: settings)
    private lazy var updates = UpdateChecker(settings: settings)

    private var cancellables = Set<AnyCancellable>()
    private var globalTokens: [HotkeyToken] = []
    /// The most recent capture, so "copy text from last capture" has something to work on.
    private var lastCapture: CaptureResult?
    private var recentMenuItem: NSMenuItem?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--ocr-test") {
            Task { exit(await OCRSelfTest.run()) }
            return
        }
        if CommandLine.arguments.contains("--menu-bar-status") {
            print(MenuBarStatus.report(settings: settings))
            exit(0)
        }
        if CommandLine.arguments.contains("--uninstall-plan") {
            Uninstaller.printPlan()
            exit(0)
        }
        if CommandLine.arguments.contains("--login-item-status") {
            print(LoginItem.diagnosticReport)
            exit(0)
        }
        if CommandLine.arguments.contains("--dump-shortcuts") {
            exit(ShortcutDump.run(bindings: bindings))
        }
        if let i = CommandLine.arguments.firstIndex(of: "--setup-demo") {
            let seconds = CommandLine.arguments.count > i + 1 ? Double(CommandLine.arguments[i + 1]) ?? 6 : 6
            let blocked = CommandLine.arguments.contains("--blocked")
            let guide = CommandLine.arguments.contains("--guide")
            Task { exit(await SetupDemo.run(settings: settings, bindings: bindings, seconds: seconds,
                                            forceBlocked: blocked, openGuide: guide)) }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--settings-demo") {
            let name = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "general"
            let seconds = CommandLine.arguments.count > i + 2 ? Double(CommandLine.arguments[i + 2]) ?? 6 : 6
            let tab = SettingsTab(rawValue: name) ?? .general
            Task { exit(await SettingsDemo.run(settings: settings, bindings: bindings, tab: tab, seconds: seconds)) }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--preview-demo") {
            let seconds = CommandLine.arguments.count > i + 1
                ? Double(CommandLine.arguments[i + 1]) ?? 6 : 6
            let portrait = CommandLine.arguments.contains("--portrait")
            Task { exit(await PreviewDemo.run(settings: settings, seconds: seconds,
                                              portrait: portrait)) }
            return
        }
        if CommandLine.arguments.contains("--settings-test") {
            Task { exit(await SettingsSelfTest.run(settings: settings, bindings: bindings)) }
            return
        }
        if CommandLine.arguments.contains("--preview-test") {
            Task { exit(await PreviewSelfTest.run(settings: settings)) }
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            Task { exit(await SelfTest.run(settings: settings)) }
            return
        }
        if CommandLine.arguments.contains("--install-update") {
            let downloadOnly = CommandLine.arguments.contains("--download-only")
            Task {
                exit(await UpdateInstallCLI.run(settings: settings, downloadOnly: downloadOnly))
            }
            return
        }
        if CommandLine.arguments.contains("--update-check") {
            Task { exit(await UpdateSelfTest.run(settings: settings)) }
            return
        }

        setStatusItem(visible: settings.showMenuBarIcon)
        wire()
        registerGlobalHotkeys()

        // Unsaved captures live in scratch indefinitely otherwise, and with automatic saving off
        // by default that is now the ordinary path rather than a corner case.
        ScratchCleaner.prune()

        // Re-register once setup closes: the user may have freed up a system shortcut, or taken
        // the offer to move Snapper onto ⌥⌘ combinations instead.
        setup.onFinish = { [weak self] in
            self?.registerGlobalHotkeys()
            self?.rebuildStatusMenu()
        }
        setup.showIfNeeded()

        if !PermissionsChecker.hasScreenRecordingAccess {
            PermissionsChecker.requestScreenRecordingAccess()
        }

        scheduleAutomaticUpdateCheck()
    }

    // MARK: - Updates

    /// Launch is already competing with the setup window and the permission prompt, and an update
    /// is never urgent, so the check waits for that to settle. It stays silent unless there is
    /// something to say: a failed automatic check is not worth an alert nobody asked for.
    private func scheduleAutomaticUpdateCheck() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, let outcome = await self.updates.checkIfDue() else { return }
            guard case .updateAvailable(let release) = outcome else { return }
            UpdatePresenter.presentAvailable(release, current: self.updates.currentVersion) { [weak self] in
                guard let self else { return }
                self.updates.skip(release)
            }
        }
    }

    /// The menu item. Unlike the automatic check this always reports back, including failures —
    /// someone who asked is waiting for an answer.
    @objc private func checkForUpdates() {
        guard !updates.isChecking else { return }
        Task { [weak self] in
            guard let self else { return }
            switch await self.updates.check() {
            case .updateAvailable(let release):
                UpdatePresenter.presentAvailable(release, current: self.updates.currentVersion) { [weak self] in
                    self?.updates.skip(release)
                }
            case .upToDate:
                UpdatePresenter.presentUpToDate(current: self.updates.currentVersion)
            case .failed(let error):
                UpdatePresenter.presentFailure(error)
            }
        }
    }

    // MARK: - Wiring

    private func wire() {
        // dropFirst because subscribing to a @Published delivers the current value straight away,
        // and the launch path has already dealt with that — without it, starting up with the icon
        // hidden would announce it as though the user had just switched it off.
        settings.$showMenuBarIcon
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] visible in
                guard let self else { return }
                self.setStatusItem(visible: visible)
                if !visible {
                    // The only way back to Settings, so it is worth saying out loud rather than
                    // leaving someone to discover that the app has apparently vanished.
                    HUD.shared.show("Menu bar icon hidden — open \(AppInfo.name) again for Settings",
                                    style: .info, duration: 4)
                }
            }
            .store(in: &cancellables)

        coordinator.onCaptured = { [weak self] result in
            guard let self else { return }
            self.lastCapture = result
            if self.settings.historyEnabled {
                self.history.record(result, limit: self.settings.historyLimit)
            }
            self.preview.show(result)
        }

        coordinator.onTextCapture = { [weak self] result in
            guard let self else { return }
            self.lastCapture = result
            self.ocr.recognize(result, keepImage: true)

            // A text grab captures pixels only so they can be read, and reading works from the
            // image already in memory rather than from the file. With no preview offered there is
            // nothing left that could use it, so it goes now instead of sitting in scratch for a
            // week — asking for text should not quietly produce a screenshot.
            //
            // Only ever the scratch file from this grab: the quick action that reads text from a
            // capture the user *did* take goes through a different path, and deleting that one
            // would destroy their screenshot.
            if !self.settings.keepOCRImage, result.isTemporary {
                try? FileManager.default.removeItem(at: result.fileURL)
            }
        }

        coordinator.onError = { message in
            HUD.shared.show(message, style: .failure, duration: 3)
        }

        coordinator.onPermissionNeeded = {
            HUD.shared.show("Screen Recording permission is required", style: .failure, duration: 3)
            PermissionsChecker.openScreenRecordingSettings()
        }

        // A quick action fired while the preview is up.
        preview.onAction = { [weak self] action, result in
            self?.runner.run(action, on: result)
        }
        preview.onOpen = { result in
            NSWorkspace.shared.open(result.fileURL)
        }

        runner.onRequestDismiss = { [weak self] in
            self?.preview.dismiss()
        }
        runner.onResultUpdated = { [weak self] result in
            guard let self else { return }
            self.lastCapture = result
            self.preview.update(with: result)
            if self.settings.historyEnabled {
                self.history.record(result, limit: self.settings.historyLimit)
            }
        }
        runner.onRequestOCR = { [weak self] result in
            self?.preview.dismiss()
            self?.ocr.recognize(result, keepImage: false)
        }
        runner.onRequestMarkup = { [weak self] result in
            guard let self else { return }
            // The editor takes focus, so the preview's key grab has to end first.
            self.preview.dismiss()
            self.markup.open(result)
        }

        // Closing the editor hands the marked-up capture back, so everything downstream — the
        // preview's quick actions, "copy text from last capture", the history entry — works on what
        // the user just drew rather than on the original.
        markup.onEdited = { [weak self] edited in
            guard let self else { return }
            self.lastCapture = edited
            if self.settings.historyEnabled {
                self.history.record(edited, limit: self.settings.historyLimit)
            }
            // Back to where they were before markup was invoked, with the edits in place.
            self.preview.show(edited)
        }

        markup.onSaved = { [weak self] url in
            guard let self, self.settings.historyEnabled,
                  let (image, scale) = try? ScreencaptureCLIEngine.loadImage(at: url) else { return }
            let saved = CaptureResult(fileURL: url, image: image, scale: scale, mode: .region, isTemporary: false)
            self.history.record(saved, limit: self.settings.historyLimit)
        }

        // An OCR grab still shows a preview, so its quick actions work on the image too.
        ocr.onKeepImage = { [weak self] result in
            self?.preview.show(result)
        }

        ocr.onReview = { [weak self] outcome, _ in
            guard let self else { return }
            // The review window takes focus, which would otherwise strand a live key grab.
            self.preview.dismiss()
            self.reviewPanel.show(outcome) { edited in
                ClipboardWriter.write(text: edited)
                HUD.shared.show("Copied \(edited.count) characters")
            }
        }
    }

    // MARK: - Hotkeys

    private func registerGlobalHotkeys() {
        HotkeyManager.shared.unregister(globalTokens)
        globalTokens = []

        var unavailable: Set<GlobalAction> = []
        for action in GlobalAction.allCases {
            let hotkey = bindings.hotkey(for: action)
            guard let token = HotkeyManager.shared.register(hotkey, handler: { [weak self] in
                self?.perform(action)
            }) else {
                // Owned by another app. Recorded so the Shortcuts tab can say so, instead of the
                // shortcut just quietly never working.
                NSLog("[Snapper] could not register \(action.title) (\(hotkey.displayString)) — another app owns it")
                unavailable.insert(action)
                continue
            }
            globalTokens.append(token)
        }
        HotkeyRegistry.shared.record(unavailable: unavailable)
    }

    private func perform(_ action: GlobalAction) {
        switch action {
        case .captureRegion:
            coordinator.capture(mode: .region)
        case .captureWindow:
            coordinator.capture(mode: .window)
        case .captureFullScreen:
            coordinator.capture(mode: .fullScreen(displayIndex: 1))
        case .ocrRegion:
            coordinator.capture(mode: .regionForOCR)
        case .ocrLastCapture:
            guard let lastCapture else {
                HUD.shared.show("Nothing captured yet", style: .info)
                return
            }
            ocr.recognize(lastCapture, keepImage: false)
        }
    }

    // MARK: - Menu bar

    /// Adds or removes the menu bar icon. Removing it rather than leaving an invisible item behind
    /// keeps the menu bar's spacing honest for everything else sitting in it.
    private func setStatusItem(visible: Bool) {
        guard visible else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: AppInfo.name
        )
        item.button?.image?.isTemplate = true
        let menu = buildMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        for action in GlobalAction.allCases {
            let item = NSMenuItem(title: action.title, action: #selector(menuActionSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            // Shown for discoverability; the Carbon registration is what actually fires them.
            item.badge = NSMenuItemBadge(string: bindings.hotkey(for: action).displayString)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        menu.addItem(recentItem)
        recentMenuItem = recentItem

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // A direct route to the recorders, rather than expecting people to go hunting for the tab.
        let shortcutsItem = NSMenuItem(title: "Keyboard Shortcuts…", action: #selector(openShortcuts), keyEquivalent: "")
        shortcutsItem.target = self
        menu.addItem(shortcutsItem)

        let setupItem = NSMenuItem(title: "Set Up \(AppInfo.name)…", action: #selector(openSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// Rebuilt each time the menu opens, so the list is never stale.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        rebuildRecentMenu()
    }

    private func rebuildRecentMenu() {
        guard let recentMenuItem else { return }
        let submenu = NSMenu()

        let recents = Array(history.entries.prefix(12))
        if recents.isEmpty {
            let empty = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short

            for entry in recents {
                let item = NSMenuItem(
                    title: "\(entry.modeName) · \(formatter.string(from: entry.createdAt))",
                    action: #selector(recentSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry.id.uuidString
                item.badge = NSMenuItemBadge(string: entry.dimensionsLabel)
                if let thumbnail = history.thumbnailImage(for: entry) {
                    thumbnail.size = NSSize(width: 32, height: 32 * thumbnail.size.height / max(1, thumbnail.size.width))
                    item.image = thumbnail
                }
                submenu.addItem(item)
            }

            submenu.addItem(.separator())
            let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clear.target = self
            submenu.addItem(clear)
        }

        recentMenuItem.submenu = submenu
    }

    /// Re-showing the preview is also how a past capture gets its quick actions back.
    @objc private func recentSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let entry = history.entries.first(where: { $0.id.uuidString == raw })
        else { return }

        guard let result = history.load(entry) else {
            HUD.shared.show("That file is no longer there", style: .failure)
            history.remove(entry)
            return
        }
        lastCapture = result
        preview.show(result)
    }

    @objc private func clearHistory() {
        history.clear()
    }

    @objc private func menuActionSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = GlobalAction(rawValue: raw) else { return }
        perform(action)
    }

    /// Opening the app while it is already running brings up Settings.
    ///
    /// macOS does not start a second copy: it sends the running one a reopen event. An accessory
    /// app has no window to unminiaturize and no document to open, so AppKit's default handling
    /// does nothing whatsoever — double-clicking Snapper in the Applications folder appeared to be
    /// broken. Settings is the only thing there is to show.
    public func applicationShouldHandleReopen(_ sender: NSApplication,
                                              hasVisibleWindows: Bool) -> Bool {
        if setup.isShowing {
            // First-run setup is the one thing that should not be buried by this.
            setup.show()
        } else {
            settingsWindow.show(tab: .general)
        }
        // Handled here. Returning true would hand back to AppKit's default, which for an app with
        // no visible windows and no documents is a no-op.
        return false
    }

    @objc private func openSettings() {
        settingsWindow.show(tab: .general)
    }

    @objc private func openShortcuts() {
        settingsWindow.show(tab: .shortcuts)
    }

    @objc private func openSetup() {
        setup.show()
    }

    /// Rebuilt so the badges show the shortcuts that are actually bound now.
    private func rebuildStatusMenu() {
        let menu = buildMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }
}
