import Foundation
import SnapperKit

/// Guards on what the uninstaller is allowed to delete.
///
/// This is the one piece of the app that removes files the user cannot get back, so the interesting
/// assertions are not "does it work" but "can it ever point somewhere it should not". A typo in a
/// path that reached `removeItem` would take a shared Library folder with it.
enum UninstallTests {

    static func run() {
        Harness.suite("Uninstaller — what it may remove") {
            let plan = Uninstaller.plan()
            let fileTargets = plan.compactMap(\.url)
            let library = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library").standardizedFileURL.path
            // The app's own location is checked separately below. Identified by identity rather
            // than by a ".app" extension, because a development build has neither.
            let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
            let dataTargets = fileTargets.filter { $0.standardizedFileURL.path != bundlePath }

            Harness.test("covers every location the app writes to") {
                // Five file locations, plus the login item and the app itself.
                Harness.expect(plan.count == 7, "got \(plan.count) items")
            }

            Harness.test("every file it would remove lives in ~/Library") {
                for url in dataTargets {
                    Harness.expect(url.standardizedFileURL.path.hasPrefix(library + "/"),
                                   "outside Library: \(url.path)")
                }
            }

            Harness.test("every file it would remove is named for this app") {
                for url in dataTargets {
                    Harness.expect(url.path.contains(AppInfo.bundleIdentifier),
                                   "not specific to Snapper: \(url.path)")
                }
            }

            Harness.test("never targets a folder shared with other apps") {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let shared = Set([
                    home,
                    home.appending(path: "Library"),
                    home.appending(path: "Library/Preferences"),
                    home.appending(path: "Library/Application Support"),
                    home.appending(path: "Library/Caches"),
                    home.appending(path: "Library/HTTPStorages"),
                    home.appending(path: "Library/Saved Application State"),
                ].map(\.standardizedFileURL.path))

                for url in fileTargets {
                    Harness.expect(!shared.contains(url.standardizedFileURL.path),
                                   "would remove a shared folder: \(url.path)")
                }
            }

            Harness.test("no target is merely the home directory with a suffix") {
                // Catches an empty bundle identifier collapsing a path back to its parent.
                for url in dataTargets {
                    Harness.expect(url.lastPathComponent.count > ".plist".count,
                                   "suspiciously short target: \(url.path)")
                }
            }

            Harness.test("keeps the signing credentials, which are not app data") {
                // This is the regression test for a real loss: the uninstaller deleted the whole
                // support directory, taking the Developer ID private keys and the keychain
                // passwords with it. The passwords were random and stored nowhere else, so the
                // certificates had to be re-issued by Apple.
                let root = FileManager.default.temporaryDirectory
                    .appending(path: "snapper-uninstall-\(UUID().uuidString)")
                let manager = FileManager.default
                for folder in ["Scratch", "Thumbnails", "signing", "distribution"] {
                    try? manager.createDirectory(at: root.appending(path: folder),
                                                 withIntermediateDirectories: true)
                }
                try? "x".write(to: root.appending(path: "history.json"),
                               atomically: true, encoding: .utf8)
                try? "secret".write(to: root.appending(path: "distribution/keychain-password"),
                                    atomically: true, encoding: .utf8)
                defer { try? manager.removeItem(at: root) }

                MainActor.assumeIsolated {
                    let outcome = Uninstaller.clearSupportDirectory(root)
                    Harness.expect(outcome.kept.sorted() == ["distribution", "signing"],
                                   "kept \(outcome.kept)")
                    Harness.expect(manager.fileExists(
                        atPath: root.appending(path: "distribution/keychain-password").path),
                                   "the keychain password was deleted again")
                    // The actual app data still has to go.
                    Harness.expect(!manager.fileExists(atPath: root.appending(path: "Scratch").path))
                    Harness.expect(!manager.fileExists(atPath: root.appending(path: "Thumbnails").path))
                    Harness.expect(!manager.fileExists(atPath: root.appending(path: "history.json").path))
                }
            }

            Harness.test("removes the folder outright when there is nothing to preserve") {
                // An ordinary user has no credential folders, so an uninstall should leave nothing.
                let root = FileManager.default.temporaryDirectory
                    .appending(path: "snapper-uninstall-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: root.appending(path: "Scratch"),
                                                         withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }
                MainActor.assumeIsolated {
                    let outcome = Uninstaller.clearSupportDirectory(root)
                    Harness.expect(outcome.kept.isEmpty)
                    Harness.expect(!FileManager.default.fileExists(atPath: root.path),
                                   "an empty support folder was left behind")
                }
            }

            Harness.test("refuses to bin a build directory") {
                // The suite runs as a plain executable, which is precisely the case that has to be
                // refused: there is no installed app here, only build output.
                Harness.expect(!Uninstaller.isRunningFromAppBundle,
                               "test runner should not look like an app bundle")
                Harness.expect(plan.last?.exists == false,
                               "offered to remove something that is not an installed app")
            }
        }
    }
}
