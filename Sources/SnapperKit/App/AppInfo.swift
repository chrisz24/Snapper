import Foundation

/// Single source of truth for the app's identity.
/// Renaming the app means changing these two constants and nothing else.
public enum AppInfo {
    public static let name = "Snapper"
    public static let bundleIdentifier = "com.zikopoulos.snapper"

    /// Where releases are published, and therefore where the updater looks. A fork only has to
    /// change these two lines.
    public static let repositoryOwner = "chrisz24"
    public static let repositoryName = "Snapper"

    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// `version` parsed for comparison. Nil outside an app bundle, where it reads "dev".
    public static var currentVersion: AppVersion? { AppVersion(version) }

    public static var repositoryURL: URL {
        URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)")!
    }

    public static var releasesPageURL: URL {
        repositoryURL.appending(path: "releases")
    }

    /// The whole release list rather than `/releases/latest`, because GitHub's "latest" is the most
    /// recently published tag, not the highest version — re-publishing an old tag would otherwise
    /// look like a downgrade to everyone. `UpdateResolver` picks the highest version instead.
    public static var releasesAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases?per_page=30")!
    }

    /// ~/Library/Application Support/<bundle id>, created on first access.
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Scratch space for captures that have not been given a permanent home yet.
    public static var scratchDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("Scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
