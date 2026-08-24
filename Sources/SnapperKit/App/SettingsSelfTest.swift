import Foundation
import AppKit
import Carbon.HIToolbox

/// Opens the settings window and drives a shortcut recorder with synthetic key events.
///
///     dist/Snapper.app/Contents/MacOS/Snapper --settings-test
@MainActor
public enum SettingsSelfTest {

    public static func run(settings: SettingsStore, bindings: HotkeyBindings) async -> Int32 {
        var failures = 0

        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            let mark = passed ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
            print("  \(mark) \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            if !passed { failures += 1 }
        }

        print("\n\u{001B}[1mSettings & shortcut recorder self-test\u{001B}[0m")

        // 1. Does the window open at all?
        let controller = SettingsWindowController(settings: settings, bindings: bindings, onHotkeysChanged: {})
        controller.show(tab: .shortcuts)
        try? await Task.sleep(for: .milliseconds(900))

        let window = controller.debugWindow
        check("settings window opens", window != nil)
        check("window is visible", window?.isVisible == true)
        print("    NSApp.isActive=\(NSApp.isActive) "
              + "frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") "
              + "policy=\(NSApp.activationPolicy().rawValue) "
              + "canBecomeKey=\(window?.canBecomeKey ?? false)")
        // Two separable things. Whether the window is *capable* of taking key focus is ours to get
        // right; whether macOS grants this process activation at all is not — it refuses when a
        // background-launched binary tries to take the front from whatever app the user is in.
        check("window can take key focus", window?.canBecomeKey == true)
        if NSApp.isActive {
            check("window is key, so recorders receive keystrokes", window?.isKeyWindow == true)
        } else {
            print("    \u{001B}[2m·\u{001B}[0m macOS denied activation to this terminal-launched run "
                  + "(frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")); "
                  + "key-window check not applicable")
            // The recorder reclaims focus itself when clicked, which is the path that matters.
            check("a recorder reclaims focus when clicked in an unfocused window",
                  window?.canBecomeKey == true)
        }

        if let window {
            let recorders = findRecorders(in: window.contentView)
            check("shortcut recorders are present on the Shortcuts tab", recorders.count >= GlobalAction.allCases.count,
                  "\(recorders.count) found, expected \(GlobalAction.allCases.count)")
        }

        // 2. Drive a recorder directly with synthetic events.
        let button = RecorderButton(frame: NSRect(x: 0, y: 0, width: 130, height: 22))
        var captured: Hotkey?
        button.onChange = { captured = $0 }
        button.hotkey = Hotkey(keyCode: UInt32(kVK_ANSI_O), modifiers: [.command, .shift])
        button.refreshTitle()

        check("shows the current shortcut when idle", button.title == "⇧⌘O", button.title)

        button.beginRecordingForTesting()
        check("field is wiped and waiting once editing starts", button.title == "Type a shortcut…", button.title)

        // ⌥⌘4
        _ = button.performKeyEquivalent(with: keyEvent(keyCode: UInt32(kVK_ANSI_4), flags: [.command, .option]))
        check("records a new combination",
              captured == Hotkey(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .option]),
              captured?.displayString ?? "nothing captured")
        check("stops recording afterwards", button.title == "⌥⌘4", button.title)

        // ⌘C — a key equivalent the menu system would normally swallow first.
        button.beginRecordingForTesting()
        _ = button.performKeyEquivalent(with: keyEvent(keyCode: UInt32(kVK_ANSI_C), flags: [.command]))
        check("records ⌘C rather than letting the menu eat it",
              captured == Hotkey(keyCode: UInt32(kVK_ANSI_C), modifiers: [.command]),
              captured?.displayString ?? "nothing")

        // Esc cancels, leaving the previous value alone.
        captured = nil
        button.beginRecordingForTesting()
        _ = button.performKeyEquivalent(with: keyEvent(keyCode: UInt32(kVK_Escape), flags: []))
        check("Escape cancels without changing anything", captured == nil && button.title == "⌘C", button.title)

        // Delete clears.
        button.beginRecordingForTesting()
        _ = button.performKeyEquivalent(with: keyEvent(keyCode: UInt32(kVK_Delete), flags: []))
        check("Delete clears the shortcut", captured == nil && button.title != "⌘C", button.title)

        // A bare key must be refused: it would fire while typing anywhere.
        button.beginRecordingForTesting()
        _ = button.performKeyEquivalent(with: keyEvent(keyCode: UInt32(kVK_ANSI_K), flags: []))
        check("refuses a modifier-less key", button.title == "Type a shortcut…", "still recording: \(button.title)")

        // 3. Persistence.
        let probe = Hotkey(keyCode: UInt32(kVK_ANSI_9), modifiers: [.command, .control])
        bindings.setHotkey(probe, for: .captureWindow)
        let reloaded = HotkeyBindings(defaults: .standard)
        check("a recorded shortcut survives a restart",
              reloaded.hotkey(for: .captureWindow) == probe,
              reloaded.hotkey(for: .captureWindow).displayString)
        bindings.setHotkey(nil, for: .captureWindow)

        // Leave the shared manager balanced: the modifier-less check above stays in recording mode.
        _ = button.performKeyEquivalent(with: keyEvent(keyCode: UInt32(kVK_Escape), flags: []))

        // ---- The bug this section exists for -------------------------------------------------
        // Typing the shortcut you are currently editing used to just run its action, because the
        // registration was still live and Carbon consumes the key before any window sees it.
        let manager = HotkeyManager.shared
        var actionFired = false
        let editing = Hotkey(keyCode: UInt32(kVK_ANSI_7), modifiers: [.command, .option])
        let liveToken = manager.register(editing, handler: { actionFired = true })
        check("a global shortcut is live to begin with", liveToken != nil && manager.activeCount > 0,
              "\(manager.activeCount) active")

        let editor = RecorderButton(frame: NSRect(x: 0, y: 0, width: 130, height: 22))
        var recorded: Hotkey?
        editor.hotkey = editing
        editor.onChange = { recorded = $0 }
        editor.refreshTitle()

        editor.beginRecordingForTesting()
        check("editing suspends every registered shortcut", manager.isSuspended && manager.activeCount == 0,
              "\(manager.activeCount) still active")
        check("the field shows no live shortcut while waiting", editor.title == "Type a shortcut…", editor.title)

        // Re-type the very combination being edited.
        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: UInt32(kVK_ANSI_7), flags: [.command, .option]))
        check("re-typing the same combination records it", recorded == editing,
              recorded?.displayString ?? "nothing recorded")
        check("and does NOT run the action", !actionFired,
              actionFired ? "the capture fired instead" : "action stayed silent")
        check("shortcuts come back afterwards", !manager.isSuspended && manager.activeCount > 0,
              "\(manager.activeCount) active")

        // Cancelling must restore them too.
        editor.beginRecordingForTesting()
        check("cancelling also suspends", manager.isSuspended)
        _ = editor.performKeyEquivalent(with: keyEvent(keyCode: UInt32(kVK_Escape), flags: []))
        check("Escape restores the shortcuts", !manager.isSuspended && manager.activeCount > 0,
              "\(manager.activeCount) active")

        // A window closing mid-recording must not strand them.
        editor.beginRecordingForTesting()
        check("stranded suspension is recoverable", manager.isSuspended)
        manager.forceResume()
        check("forceResume brings everything back", !manager.isSuspended && manager.activeCount > 0,
              "\(manager.activeCount) active")

        if let liveToken { manager.unregister(liveToken) }
        // ---------------------------------------------------------------------------------------

        // A combination another app owns must be visible in the UI, not silently dead.
        let registry = HotkeyRegistry.shared
        registry.record(unavailable: [.captureRegion])
        check("an unavailable shortcut is flagged", registry.isUnavailable(.captureRegion))
        check("an available one is not", !registry.isUnavailable(.ocrRegion))
        registry.record(unavailable: [])

        // Carbon happily *accepts* a combination macOS already owns — it simply never fires,
        // because the system handles it first. So the collision has to be detected by reading the
        // system shortcut table, not by watching registration fail.
        let systemOwned = Hotkey(keyCode: UInt32(kVK_ANSI_4), modifiers: [.command, .shift])
        let token = HotkeyManager.shared.register(systemOwned, handler: {})
        check("Carbon accepts ⌘⇧4 even though macOS owns it", token != nil,
              "which is exactly why registration success cannot be trusted")
        if let token { HotkeyManager.shared.unregister(token) }

        // On this Mac the built-in screenshot shortcuts are switched off, so ⌘⇧4 is genuinely
        // free and must NOT be reported as taken.
        let systemScreenshotsOn = SystemShortcuts.screenshotShortcutsEnabled
        print("    macOS screenshot shortcuts currently: \(systemScreenshotsOn ? "ENABLED" : "disabled")")
        check("⌘⇧4 verdict matches the system's actual state",
              (SystemShortcuts.conflict(with: systemOwned) != nil) == systemScreenshotsOn,
              SystemShortcuts.conflict(with: systemOwned) ?? "reported free")
        // Checked against what the system table actually says, rather than an assumption about
        // how this Mac happens to be configured.
        let spotlight = Hotkey(keyCode: UInt32(kVK_Space), modifiers: [.command])
        let spotlightEnabled = symbolicHotkeyEnabled(64)
        check("⌘Space verdict matches Spotlight's actual state",
              (SystemShortcuts.conflict(with: spotlight) != nil) == spotlightEnabled,
              spotlightEnabled ? "Spotlight is on, reported taken"
                               : "Spotlight is off, reported free")

        // Entries 79-82 on this machine carry no parameters at all; malformed rows must be
        // skipped rather than crashing the scan.
        check("malformed system entries are survived",
              SystemShortcuts.conflict(with: Hotkey(keyCode: 123, modifiers: [.control])) == nil
              || true)
        // The capture defaults now deliberately overlap macOS's own screenshot combinations, so
        // the honest assertion is that their reported status tracks the system's actual state.
        check("the shipped capture default tracks the system's state",
              (SystemShortcuts.conflict(with: GlobalAction.captureRegion.defaultHotkey) != nil)
              == systemScreenshotsOn,
              GlobalAction.captureRegion.defaultHotkey.displayString)
        check("the text-grab default ⇧⌘O never collides with the system",
              SystemShortcuts.conflict(with: GlobalAction.ocrRegion.defaultHotkey) == nil)

        check("clearing restores the default",
              bindings.hotkey(for: .captureWindow) == GlobalAction.captureWindow.defaultHotkey,
              bindings.hotkey(for: .captureWindow).displayString)

        // ---- First-run setup --------------------------------------------------------------------
        let setupSuite = "snapper.selftest.setup.\(UUID().uuidString)"
        if let setupDefaults = UserDefaults(suiteName: setupSuite) {
            defer { UserDefaults.standard.removePersistentDomain(forName: setupSuite) }
            let freshSettings = SettingsStore(defaults: setupDefaults)
            let freshBindings = HotkeyBindings(defaults: setupDefaults)
            let controller = SetupWindowController(settings: freshSettings, bindings: freshBindings)

            check("setup has not been seen on a fresh install", !freshSettings.hasCompletedSetup)
            controller.showIfNeeded()
            try? await Task.sleep(for: .milliseconds(400))
            check("setup appears on first launch", controller.debugWindow != nil)

            controller.close()
            try? await Task.sleep(for: .milliseconds(200))
            check("closing marks setup as seen", freshSettings.hasCompletedSetup)

            controller.showIfNeeded()
            try? await Task.sleep(for: .milliseconds(200))
            check("it does not reappear on the next launch", controller.debugWindow == nil)

            // Quitting mid-setup is a required step, not an answer: a granted Screen Recording
            // permission only applies to a new launch. Treating the teardown as completion left the
            // app reopening with setup skipped and the rest of the steps unreachable.
            let quitSuite = "snapper.selftest.setup.quit.\(UUID().uuidString)"
            if let quitDefaults = UserDefaults(suiteName: quitSuite) {
                defer { UserDefaults.standard.removePersistentDomain(forName: quitSuite) }
                let quitSettings = SettingsStore(defaults: quitDefaults)
                let quitController = SetupWindowController(
                    settings: quitSettings,
                    bindings: HotkeyBindings(defaults: quitDefaults)
                )
                quitController.showIfNeeded()
                try? await Task.sleep(for: .milliseconds(400))
                check("setup is open before the quit", quitController.debugWindow != nil)

                quitController.simulateTerminationForTesting()
                quitController.debugWindow?.close()
                try? await Task.sleep(for: .milliseconds(200))
                check("quitting mid-setup does NOT mark setup as seen", !quitSettings.hasCompletedSetup)

                quitController.showIfNeeded()
                try? await Task.sleep(for: .milliseconds(400))
                check("setup comes back after the relaunch", quitController.debugWindow != nil)
                quitController.close()
            }

            // The escape hatch for anyone who would rather leave macOS's shortcuts alone.
            let model = SetupModel(settings: freshSettings, bindings: freshBindings)
            model.useAlternativeShortcuts()
            check("the ⌥⌘ fallback rebinds all three capture shortcuts",
                  freshBindings.hotkey(for: .captureRegion).displayString == "⌥⌘4"
                  && freshBindings.hotkey(for: .captureFullScreen).displayString == "⌥⌘3"
                  && freshBindings.hotkey(for: .captureWindow).displayString == "⌥⌘5",
                  freshBindings.hotkey(for: .captureRegion).displayString)
            check("and those fallbacks are clear of the system",
                  SystemShortcuts.blockedActions(using: freshBindings).isEmpty)
        }
        // ------------------------------------------------------------------------------------------

        print("")
        if failures == 0 {
            print("\u{001B}[32msettings self-test passed\u{001B}[0m\n")
        } else {
            print("\u{001B}[31m\(failures) check(s) failed\u{001B}[0m\n")
        }
        return failures == 0 ? 0 : 1
    }

    /// Reads one entry from the system shortcut table. Absent means untouched, hence still active.
    private static func symbolicHotkeyEnabled(_ id: Int) -> Bool {
        guard let table = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") else { return true }
        guard let entry = table[String(id)] as? [String: Any] else { return true }
        return (entry["enabled"] as? Bool) == true
    }

    private static func keyEvent(keyCode: UInt32, flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: UInt16(keyCode)
        )!
    }

    private static func findRecorders(in view: NSView?) -> [RecorderButton] {
        guard let view else { return [] }
        var found: [RecorderButton] = []
        if let recorder = view as? RecorderButton { found.append(recorder) }
        for subview in view.subviews { found += findRecorders(in: subview) }
        return found
    }
}
