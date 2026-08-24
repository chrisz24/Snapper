import Foundation

/// Live check of the update path, so a release can be verified from the command line rather than
/// by waiting to see whether anyone gets prompted:
///
///     dist/Snapper.app/Contents/MacOS/Snapper --update-check
///
/// It talks to the real GitHub API. It needs no permissions and changes nothing except the
/// stored "last checked" timestamp.
@MainActor
public enum UpdateSelfTest {

    public static func run(settings: SettingsStore) async -> Int32 {
        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            let mark = passed ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
            print("  \(mark) \(label)\(detail.isEmpty ? "" : " — \(detail)")")
        }

        print("\n\u{001B}[1mSnapper update check\u{001B}[0m")
        print("  repository: \(AppInfo.repositoryOwner)/\(AppInfo.repositoryName)")
        print("  endpoint:   \(AppInfo.releasesAPIURL.absoluteString)")
        print("  installed:  \(AppInfo.version) (build \(AppInfo.build))")
        if AppInfo.currentVersion == nil {
            print("  \u{001B}[33mnote\u{001B}[0m: this binary is not in an app bundle, so it reports version"
                  + " \"\(AppInfo.version)\" and is treated as 0.0.0 — every release will look newer.")
        }
        if !settings.skippedUpdateVersion.isEmpty {
            print("  skipped:    \(settings.skippedUpdateVersion) (ignored by an explicit check)")
        }
        print("")

        let checker = UpdateChecker(settings: settings)
        let outcome = await checker.check()

        switch outcome {
        case .upToDate:
            check("reached GitHub", true)
            check("nothing newer than \(checker.currentVersion.displayString)", true)
            print("\n\u{001B}[32mup to date\u{001B}[0m\n")
            return 0

        case .updateAvailable(let release):
            check("reached GitHub", true)
            check("found \(release.version.displayString)", true, "tag \(release.tag)")
            if let asset = release.asset {
                let size = asset.sizeLabel
                check("has a downloadable build", true, size.isEmpty ? asset.name : "\(asset.name), \(size)")
                if asset.name.lowercased().hasSuffix(".pkg") {
                    check("installs in place", true, "Install downloads and verifies it, then hands it to Installer")
                } else {
                    check("installs in place", false, "not a .pkg — Install falls back to opening a browser")
                }
            } else {
                check("has a downloadable build", false,
                      "no .pkg/.dmg/.zip attached — Download would open the release page instead")
            }
            if let team = UpdateInstaller.runningTeamIdentifier {
                check("update will be pinned to team \(team)", true, "a package signed by anyone else is refused")
            } else {
                check("team pinning unavailable", false,
                      "this build is unsigned, so only Apple notarization is checked")
            }
            check("release notes present", !release.notes.isEmpty,
                  release.notes.isEmpty ? "the alert will have no notes panel" : "\(release.notes.count) characters")
            if release.isPrerelease { print("  ⓘ flagged as a pre-release") }
            print("\n  \(release.downloadURL.absoluteString)")
            print("\n\u{001B}[32mupdate available: \(release.version.displayString)\u{001B}[0m\n")
            return 0

        case .failed(let error):
            check("reached GitHub", false, error.errorDescription ?? "unknown error")
            print("\n\u{001B}[31mcheck failed\u{001B}[0m\n")
            return 1
        }
    }
}
