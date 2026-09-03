import Foundation
import AppKit

/// Removes everything Snapper has put on this Mac.
///
/// Worth stating what "everything" can and cannot cover. The files below are all owned by the
/// user, so they go without ceremony. Two things are different: the app bundle itself, which is
/// moved to the Trash and will refuse if it sits somewhere the user cannot write (an app copied
/// into /Applications with an admin prompt ends up owned by root), and the Screen Recording
/// permission, which lives in a system database no app may edit. Both are reported rather than
/// silently skipped.
public enum Uninstaller {

    public struct Item: Identifiable {
        public let id = UUID()
        public let label: String
        public let detail: String
        /// Nil for anything that is not a file, such as the login-item registration.
        public let url: URL?
        public let exists: Bool
    }

    public struct Report {
        public var removed: [String] = []
        public var failed: [String] = []
        /// Things the user has to finish by hand, with the reason.
        public var manual: [String] = []

        public var isClean: Bool { failed.isEmpty && manual.isEmpty }
    }

    // MARK: - What is there

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    private static var id: String { AppInfo.bundleIdentifier }

    /// The app's own folder, cleared out rather than removed outright — see `preservedInSupport`.
    private static var supportDirectory: URL {
        home.appending(path: "Library/Application Support/\(id)")
    }

    /// Folders inside the support directory that are *not* app data and must survive an uninstall.
    ///
    /// `scripts/setup-developer-id.sh` keeps the Developer ID private keys and the signing
    /// keychains' passwords here, because there is nowhere better for them on a machine with no
    /// Xcode. Deleting them is not a tidy-up: the passwords are randomly generated and stored
    /// nowhere else, so the keychains can never be unlocked again, and the private keys cannot be
    /// reconstructed — the certificates have to be re-issued by Apple. That happened once, to the
    /// author of this file, which is why it is a list and not a comment.
    ///
    /// No end user has either folder, so keeping them costs an ordinary uninstall nothing.
    public static let preservedInSupport = ["signing", "distribution"]

    /// Every other file location the app writes to, in the order they are removed.
    private static var dataLocations: [(label: String, detail: String, url: URL)] {
        let library = home.appending(path: "Library")
        return [
            ("Settings", "Preferences",
             library.appending(path: "Preferences/\(id).plist")),
            ("Caches", "Caches",
             library.appending(path: "Caches/\(id)")),
            ("Update-check cache", "HTTPStorages",
             library.appending(path: "HTTPStorages/\(id)")),
            ("Saved window state", "Saved Application State",
             library.appending(path: "Saved Application State/\(id).savedState")),
        ]
    }

    /// What removal would cover, for a confirmation that lists it rather than asking for trust.
    public static func plan() -> [Item] {
        var items: [Item] = [supportItem]
        items += dataLocations.map { location in
            let exists = FileManager.default.fileExists(atPath: location.url.path)
            return Item(label: location.label,
                        detail: exists ? "\(location.detail) — \(size(of: location.url))"
                                       : "\(location.detail) — nothing stored",
                        url: location.url,
                        exists: exists)
        }

        items.append(Item(label: "Open at login",
                          detail: LoginItem.isEnabled ? "registered — will be unregistered"
                                                      : "not registered",
                          url: nil,
                          exists: LoginItem.isEnabled))

        let bundle = Bundle.main.bundleURL
        let bundleDetail: String
        if !isRunningFromAppBundle {
            // A development build runs straight out of .build, and that directory is a build
            // artefact, not an installed app. Offering to bin it would be actively wrong.
            bundleDetail = "not an installed app — \(bundle.path) is left alone"
        } else if canTrashBundle {
            bundleDetail = "moved to the Trash — \(bundle.path)"
        } else {
            bundleDetail = "cannot be moved — \(bundle.path)"
        }
        items.append(Item(label: "The \(AppInfo.name) app itself",
                          detail: bundleDetail,
                          url: bundle,
                          exists: isRunningFromAppBundle))
        return items
    }

    /// The support directory's row, which says outright that credentials are kept.
    private static var supportItem: Item {
        let exists = FileManager.default.fileExists(atPath: supportDirectory.path)
        let kept = preservedFolders()
        var detail = exists ? "Application Support — \(size(of: supportDirectory))"
                            : "Application Support — nothing stored"
        if !kept.isEmpty {
            detail += " · keeping \(kept.formatted(.list(type: .and)))"
        }
        return Item(label: "Captures, history and thumbnails",
                    detail: detail,
                    url: supportDirectory,
                    exists: exists)
    }

    /// Which of the preserved folders are actually present.
    public static func preservedFolders(in directory: URL? = nil) -> [String] {
        let root = directory ?? supportDirectory
        return preservedInSupport.filter {
            FileManager.default.fileExists(atPath: root.appending(path: $0).path)
        }
    }

    /// Empties the support directory of app data, leaving the credential folders alone. Takes the
    /// directory so the suite can prove the exclusion on a copy rather than on the real one.
    @discardableResult
    public static func clearSupportDirectory(_ directory: URL) -> (removed: [String], kept: [String]) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: directory.path) else {
            return ([], [])
        }
        var removed: [String] = []
        var kept: [String] = []
        for entry in entries {
            if preservedInSupport.contains(entry) {
                kept.append(entry)
                continue
            }
            if (try? manager.removeItem(at: directory.appending(path: entry))) != nil {
                removed.append(entry)
            }
        }
        // Nothing worth keeping and nothing left: take the folder itself too.
        if kept.isEmpty, (try? manager.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
            try? manager.removeItem(at: directory)
        }
        return (removed, kept)
    }

    /// False for a development build running out of `.build`, where there is no app to remove.
    public static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Whether the bundle can be trashed by this user. An app installed into /Applications with an
    /// administrator prompt is owned by root, and moving it needs a password this app cannot ask for.
    public static var canTrashBundle: Bool {
        let bundle = Bundle.main.bundleURL
        // Deleting a directory entry needs write permission on the parent, not on the bundle.
        return FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    private static func size(of url: URL) -> String {
        var bytes: Int64 = 0
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            while let entry = enumerator?.nextObject() as? URL {
                let v = try? entry.resourceValues(
                    forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
                bytes += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
            }
        } else {
            let v = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey])
            bytes += Int64(v?.fileAllocatedSize ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Doing it

    /// Removes the lot. Call `quit()` straight afterwards: the preferences must not be written
    /// again once they have been cleared.
    @MainActor
    public static func removeEverything() -> Report {
        var report = Report()

        // First, so the machine does not try to launch an app that is about to be in the Trash.
        if LoginItem.isEnabled {
            switch LoginItem.setEnabled(false) {
            case .disabled: report.removed.append("Login item unregistered")
            case .failed(let why): report.failed.append("Login item: \(why)")
            default: report.failed.append("Login item could not be unregistered")
            }
        }

        if FileManager.default.fileExists(atPath: supportDirectory.path) {
            let outcome = clearSupportDirectory(supportDirectory)
            if !outcome.removed.isEmpty {
                report.removed.append("Captures, history and thumbnails")
            }
            if !outcome.kept.isEmpty {
                report.manual.append(
                    "Left your signing credentials in place — \(supportDirectory.path) still holds "
                    + "\(outcome.kept.formatted(.list(type: .and))). They are not app data, and "
                    + "deleting them means re-issuing certificates from Apple. Remove them by hand "
                    + "if you really mean to.")
            }
        }

        for location in dataLocations where FileManager.default.fileExists(atPath: location.url.path) {
            do {
                try FileManager.default.removeItem(at: location.url)
                report.removed.append(location.label)
            } catch {
                report.failed.append("\(location.label): \(error.localizedDescription)")
            }
        }

        // The stored settings are gone from disk, but this process still holds them in memory and
        // would write them straight back on the way out. Clearing the domain here and quitting
        // without a normal teardown is what makes the removal stick.
        UserDefaults.standard.removePersistentDomain(forName: id)
        UserDefaults.standard.synchronize()
        CFPreferencesAppSynchronize(id as CFString)

        // Screen Recording lives in a system database that no application may write to.
        if PermissionsChecker.hasScreenRecordingAccess {
            report.manual.append(
                "Screen Recording is still granted. Remove \(AppInfo.name) under System Settings › "
                + "Privacy & Security › Screen & System Audio Recording — no app is allowed to "
                + "revoke this for itself.")
        }

        let bundle = Bundle.main.bundleURL
        if !isRunningFromAppBundle {
            report.manual.append("Running from \(bundle.path), which is a build directory rather "
                                 + "than an installed app, so nothing was moved to the Trash.")
        } else if canTrashBundle {
            do {
                try FileManager.default.trashItem(at: bundle, resultingItemURL: nil)
                report.removed.append("\(AppInfo.name).app moved to the Trash")
            } catch {
                report.manual.append("Could not move \(bundle.path) to the Trash: "
                                     + "\(error.localizedDescription). Drag it there yourself.")
            }
        } else {
            report.manual.append("\(bundle.path) is not yours to move — it was installed with an "
                                 + "administrator prompt. Drag it to the Trash in Finder, which "
                                 + "will ask for your password.")
        }

        return report
    }

    /// Leaves without the usual teardown, so nothing gets a chance to persist settings again.
    public static func quit() -> Never {
        exit(0)
    }

    /// Prints what removal would cover and changes nothing, for `--uninstall-plan`.
    @MainActor
    public static func printPlan() {
        print("\n\(AppInfo.name) uninstall plan — nothing has been removed\n")
        for item in plan() {
            print("  \(item.exists ? "•" : " ") \(item.label)")
            print("      \(item.detail)")
        }
        print("\n  running from an app bundle: \(isRunningFromAppBundle ? "yes" : "no — a build directory, nothing to remove")")
        print("  bundle removable by this user: \(canTrashBundle ? "yes" : "no — needs Finder and a password")")
        print("  screen recording granted: \(PermissionsChecker.hasScreenRecordingAccess ? "yes — must be removed by hand" : "no")\n")
    }
}
