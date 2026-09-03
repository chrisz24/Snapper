import Foundation
import AppKit
import SnapperKit

enum DefaultsTests {

    static func run() {
        Harness.suite("Shipped defaults") {
            Harness.test("capture selection defaults to ⇧⌘4") {
                Harness.expectEqual(GlobalAction.captureRegion.defaultHotkey.displayString, "⇧⌘4")
            }
            Harness.test("capture screen defaults to ⇧⌘3") {
                Harness.expectEqual(GlobalAction.captureFullScreen.defaultHotkey.displayString, "⇧⌘3")
            }
            Harness.test("capture window defaults to ⇧⌘5") {
                Harness.expectEqual(GlobalAction.captureWindow.defaultHotkey.displayString, "⇧⌘5")
            }
            Harness.test("all three capture shortcuts share the ⇧⌘ pattern") {
                for action in [GlobalAction.captureFullScreen, .captureRegion, .captureWindow] {
                    Harness.expect(action.defaultHotkey.modifiers == [.command, .shift],
                                   "\(action.rawValue) is \(action.defaultHotkey.displayString)")
                }
            }
            Harness.test("setup has not been seen on a fresh install") {
                let suite = "snapper.tests.setup.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
                MainActor.assumeIsolated {
                    Harness.expect(!SettingsStore(defaults: defaults).hasCompletedSetup)
                }
            }
            Harness.test("text grab defaults to ⇧⌘O") {
                Harness.expectEqual(GlobalAction.ocrRegion.defaultHotkey.displayString, "⇧⌘O")
            }
            Harness.test("no two global defaults collide") {
                let all = GlobalAction.allCases.map(\.defaultHotkey)
                Harness.expectEqual(Set(all).count, all.count, "duplicate default shortcut")
            }
            Harness.test("no two quick-action defaults collide") {
                let all = QuickAction.allCases.map(\.defaultHotkey)
                Harness.expectEqual(Set(all).count, all.count, "duplicate default shortcut")
            }

            Harness.test("the menu bar icon is shown by default") {
                // Off by default would make a fresh install look like it had never launched.
                let suite = "snapper.tests.menubar.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
                MainActor.assumeIsolated {
                    Harness.expect(SettingsStore(defaults: defaults).showMenuBarIcon)
                }
            }

            Harness.test("a text grab does not keep the image by default") {
                // ⇧⌘O is asked for text. Previewing a screenshot nobody asked for reads as the app
                // having taken one behind your back.
                let suite = "snapper.tests.ocr.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
                MainActor.assumeIsolated {
                    let store = SettingsStore(defaults: defaults)
                    Harness.expect(!store.keepOCRImage)
                    // The text itself is still the point, so copying stays on.
                    Harness.expect(store.autoCopyOCR)
                }
            }

            Harness.test("captures are not saved automatically by default") {
                let suite = "snapper.tests.settings.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
                MainActor.assumeIsolated {
                    let store = SettingsStore(defaults: defaults)
                    Harness.expect(!store.autoSaveToDisk,
                                   "nothing should land on the Desktop unless asked for")
                }
            }
        }

        Harness.suite("Binding storage") {
            Harness.test("setting a shortcut equal to the default stores no override") {
                let suite = "snapper.tests.bindings.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

                MainActor.assumeIsolated {
                    let bindings = HotkeyBindings(defaults: defaults)
                    bindings.setHotkey(GlobalAction.captureRegion.defaultHotkey, for: .captureRegion)
                    Harness.expect(defaults.data(forKey: "hotkeys.global") == nil
                                   || (defaults.data(forKey: "hotkeys.global")?.count ?? 0) <= 2,
                                   "an override identical to the default is clutter")
                }
            }

            Harness.test("a genuine customisation is stored and survives a reload") {
                let suite = "snapper.tests.bindings.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

                MainActor.assumeIsolated {
                    let custom = Hotkey(keyCode: 9, modifiers: [.command, .control])
                    let bindings = HotkeyBindings(defaults: defaults)
                    bindings.setHotkey(custom, for: .captureRegion)

                    let reloaded = HotkeyBindings(defaults: defaults)
                    Harness.expectEqual(reloaded.hotkey(for: .captureRegion), custom)
                }
            }

            Harness.test("an override that merely restates the default is dropped on load") {
                let suite = "snapper.tests.bindings.\(UUID().uuidString)"
                guard let defaults = UserDefaults(suiteName: suite) else { return }
                defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

                // Written directly, as an older build would have stored it.
                let stale = ["captureRegion": GlobalAction.captureRegion.defaultHotkey]
                defaults.set(try? JSONEncoder().encode(stale), forKey: "hotkeys.global")

                MainActor.assumeIsolated {
                    let bindings = HotkeyBindings(defaults: defaults)
                    Harness.expectEqual(bindings.hotkey(for: .captureRegion),
                                        GlobalAction.captureRegion.defaultHotkey)
                    let remaining = defaults.data(forKey: "hotkeys.global")
                        .flatMap { try? JSONDecoder().decode([String: Hotkey].self, from: $0) } ?? [:]
                    Harness.expect(remaining.isEmpty, "\(remaining.count) redundant override(s) kept")
                }
            }
        }

        Harness.suite("ScratchCleaner") {
            Harness.test("removes stale files and keeps recent ones") {
                let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("snapper-scratch-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: dir) }

                let old = dir.appendingPathComponent("old.png")
                let fresh = dir.appendingPathComponent("fresh.png")
                try Data("old".utf8).write(to: old)
                try Data("fresh".utf8).write(to: fresh)

                let longAgo = Date(timeIntervalSinceNow: -30 * 24 * 3600)
                try FileManager.default.setAttributes([.modificationDate: longAgo], ofItemAtPath: old.path)

                let removed = ScratchCleaner.prune(in: dir, olderThan: 7 * 24 * 3600)
                Harness.expectEqual(removed, 1)
                Harness.expect(!FileManager.default.fileExists(atPath: old.path), "stale file survived")
                Harness.expect(FileManager.default.fileExists(atPath: fresh.path), "recent file was destroyed")
            }

            Harness.test("an empty or missing folder is harmless") {
                let missing = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("snapper-absent-\(UUID().uuidString)")
                Harness.expectEqual(ScratchCleaner.prune(in: missing), 0)
            }
        }
    }
}
