import AppKit

/// Brings Snapper back once an update has actually been installed.
///
/// Snapper cannot install over itself and then carry on, and it cannot know in advance how long the
/// install will take: Installer runs on its own, asks for a password, and waits for whoever is at
/// the keyboard. Quitting straight after handing the package over — which is what used to happen —
/// left the app gone whether the install succeeded, failed, or was cancelled, and reopening it was
/// left to the user.
///
/// So the running copy stays up and watches the build number recorded in its own bundle on disk.
/// Installer replacing the bundle changes that number, which is the signal to relaunch into the new
/// copy. A cancelled install never changes it, so nothing happens and the old copy simply carries
/// on — better than having quit for an update that never arrived.
///
/// The window where this process is running from a bundle that has been replaced underneath it is
/// deliberately short: the check runs every second, and relaunching is the first thing it does.
@MainActor
public enum UpdateRelauncher {

    /// Long enough for someone to find their password and read Installer's panes, bounded so a
    /// forgotten Installer window does not leave this polling for the rest of the day.
    private static let limit = Duration.seconds(600)
    private static let interval = Duration.seconds(1)

    private static var watching = false

    /// The build string in a bundle on disk, which is what an install replaces. Read from the file
    /// rather than from `Bundle.main`, whose values were loaded at launch and will not change.
    public static func installedBuild(at bundle: URL) -> String? {
        let plist = bundle.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
                  as? [String: Any]
        else { return nil }
        return info["CFBundleVersion"] as? String
    }

    /// Where the installer package puts the app. Pinned there by `make-pkg.sh`, on purpose, so an
    /// install cannot silently overwrite a build kept somewhere else.
    public static var installLocation: URL {
        URL(fileURLWithPath: "/Applications").appending(path: "\(AppInfo.name).app")
    }

    /// The bundles worth watching, given where this copy runs from.
    ///
    /// Usually one: the running copy is the copy the installer replaces. It is two when they differ
    /// — a copy started from ~/Applications, or straight out of a build directory — and watching
    /// only the running bundle would then wait for a change that lands somewhere else entirely.
    ///
    /// Pure, so the suite can check the case this exists for.
    public static func bundlesToWatch(running: URL, installLocation: URL) -> [URL] {
        var bundles: [URL] = []
        if running.pathExtension == "app" {
            bundles.append(running)
        }
        if running.standardizedFileURL != installLocation.standardizedFileURL {
            bundles.append(installLocation)
        }
        return bundles
    }

    /// Starts watching for an installed update.
    public static func relaunchWhenInstalled(onRelaunch: (() -> Void)? = nil) {
        guard !watching else { return }
        let bundles = bundlesToWatch(running: Bundle.main.bundleURL,
                                     installLocation: installLocation)
        guard !bundles.isEmpty else { return }

        // Recorded per bundle. A location that does not exist yet reads as nil, and an install
        // making it appear counts as the change — that is exactly the case where the running copy
        // lives elsewhere and would otherwise never notice.
        var before: [URL: String?] = [:]
        for bundle in bundles { before[bundle] = installedBuild(at: bundle) }

        watching = true
        Task { @MainActor in
            var waited = Duration.zero
            while waited < limit {
                try? await Task.sleep(for: interval)
                waited += interval

                for bundle in bundles {
                    let now = installedBuild(at: bundle)
                    guard now != before[bundle] ?? nil, now != nil else { continue }
                    watching = false
                    onRelaunch?()
                    // A beat so the message is on screen before the process goes.
                    try? await Task.sleep(for: .milliseconds(700))
                    // The bundle that changed, not the one that was running: after an install to
                    // /Applications those are different, and reopening the running copy would
                    // start the old version over again.
                    PermissionsChecker.relaunch(bundle)
                    return
                }
            }
            watching = false
        }
    }
}
