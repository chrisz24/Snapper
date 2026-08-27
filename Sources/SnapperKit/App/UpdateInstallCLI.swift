import AppKit

/// `--install-update`: check, download, verify, and install, from a terminal or a script.
///
///     Snapper.app/Contents/MacOS/Snapper --install-update
///     Snapper.app/Contents/MacOS/Snapper --install-update --download-only
///
/// The verification is the same as the in-app updater's, and for the same reason: the package is
/// about to run with administrator rights, so it must be signed by the team that signed this copy
/// and accepted by Gatekeeper, or it is deleted unopened.
///
/// Installing needs administrator rights, which this deliberately does not try to acquire. Running
/// the app as root would write root-owned files into the user's preferences and support folders and
/// quietly break the ordinary copy. Instead the verified package is handed to macOS's Installer,
/// which asks for the password itself — and `--download-only` prints the path so an unattended
/// caller can run `sudo installer` with it and never start a GUI at all.
public enum UpdateInstallCLI {

    public static func run(settings: SettingsStore, downloadOnly: Bool) async -> Int32 {
        func mark(_ ok: Bool) -> String {
            ok ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
        }

        print("\n\u{001B}[1m\(AppInfo.name) update install\u{001B}[0m")
        print("  installed:  \(AppInfo.version) (build \(AppInfo.build))")
        if AppInfo.currentVersion == nil {
            print("  \u{001B}[33mnote\u{001B}[0m: this binary is not in an app bundle, so it is treated as"
                  + " 0.0.0 and every release looks newer. Run the one inside Snapper.app.")
        }
        print("")

        let checker = await UpdateChecker(settings: settings)
        let outcome = await checker.check()

        let release: GitHubRelease
        switch outcome {
        case .upToDate:
            let current = await checker.currentVersion.displayString
            print("  \(mark(true)) nothing newer than \(current)")
            print("\n\u{001B}[32mup to date\u{001B}[0m\n")
            return 0
        case .failed(let error):
            print("  \(mark(false)) could not check — \(error.localizedDescription)")
            print("")
            return 1
        case .updateAvailable(let found):
            release = found
            print("  \(mark(true)) \(found.version.displayString) is available")
        }

        guard let asset = release.asset, asset.name.lowercased().hasSuffix(".pkg") else {
            print("  \(mark(false)) that release has no installer package attached")
            print("      \(release.pageURL.absoluteString)")
            print("")
            return 1
        }

        let megabytes = String(format: "%.1f", Double(asset.byteCount) / 1_048_576)
        print("  … downloading \(asset.name) (\(megabytes) MB)")

        let installer = await UpdateInstaller()
        switch await installer.fetch(release) {
        case .failure(let failure):
            print("  \(mark(false)) \(failure.errorDescription ?? "failed")")
            print("")
            return 1

        case .success(let package):
            print("  \(mark(true)) signed by the same team as this copy, and notarized")
            print("")
            print("  package: \(package.path)")
            print("")

            if downloadOnly {
                print("  Install it with:")
                print("    sudo installer -pkg \"\(package.path)\" -target /")
                print("")
                return 0
            }

            await MainActor.run { NSWorkspace.shared.open(package) }
            print("  Handed to macOS Installer, which will ask for your password.")
            print("  To install without a prompt instead, re-run with --download-only and use")
            print("  the sudo command it prints.")
            print("")
            return 0
        }
    }
}
