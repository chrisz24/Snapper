import Foundation

/// One published release, reduced to the parts the updater actually shows or opens.
public struct GitHubRelease: Sendable, Equatable, Identifiable {
    public let version: AppVersion
    /// The tag as published — `v0.2.0`. Kept verbatim so links and messages match the repo.
    public let tag: String
    public let title: String
    public let notes: String
    /// The release's page on github.com. Always present, and the fallback when there is no asset.
    public let pageURL: URL
    /// The best downloadable build attached to the release, if any.
    public let asset: Asset?
    /// Whether GitHub itself flagged this as a pre-release.
    public let isFlaggedPrerelease: Bool
    public let publishedAt: Date?

    public var id: String { tag }

    /// True if either the tag says so or GitHub says so.
    public var isPrerelease: Bool { isFlaggedPrerelease || version.isPrerelease }

    /// What "Download" should open: the build if there is one, the release page otherwise.
    public var downloadURL: URL { asset?.url ?? pageURL }

    public struct Asset: Sendable, Equatable {
        public let name: String
        public let url: URL
        public let byteCount: Int

        /// "12.4 MB", or an empty string when GitHub reported no size.
        public var sizeLabel: String {
            guard byteCount > 0 else { return "" }
            return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        }
    }
}

/// Everything that can go wrong between asking GitHub and having a release to compare against.
public enum UpdateError: LocalizedError, Equatable {
    case offline(String)
    case noReleasesPublished
    /// GitHub returned 404. Distinct from "no releases" because the causes and the fixes differ:
    /// a private, renamed, or mistyped repository looks identical to an empty one otherwise.
    case repositoryNotFound
    case rateLimited
    case badResponse(Int)
    case malformedFeed

    public var errorDescription: String? {
        switch self {
        case .offline(let detail):
            "Could not reach GitHub — \(detail)"
        case .noReleasesPublished:
            "No releases have been published yet."
        case .repositoryNotFound:
            "GitHub has no public repository at \(AppInfo.repositoryOwner)/\(AppInfo.repositoryName)."
        case .rateLimited:
            "GitHub is rate-limiting this network. Try again in a little while."
        case .badResponse(let code):
            "GitHub replied with HTTP \(code)."
        case .malformedFeed:
            "GitHub's reply could not be read."
        }
    }
}

// MARK: - Decoding

extension GitHubRelease {
    /// Decodes `GET /repos/{owner}/{repo}/releases`, dropping drafts and anything whose tag is not
    /// a version we can compare. Ordering is left to `UpdateResolver`, since GitHub sorts by
    /// creation date and a re-published older tag would otherwise come out on top.
    public static func decodeFeed(_ data: Data) throws -> [GitHubRelease] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payloads = try? decoder.decode([Payload].self, from: data) else {
            throw UpdateError.malformedFeed
        }
        return payloads.compactMap(GitHubRelease.init(payload:))
    }

    private init?(payload: Payload) {
        guard payload.draft != true else { return nil }
        guard let version = AppVersion(payload.tag_name) else { return nil }
        guard let pageURL = URL(string: payload.html_url) else { return nil }

        self.version = version
        self.tag = payload.tag_name
        // GitHub allows an empty release name and shows the tag in its place.
        let name = payload.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = name.isEmpty ? payload.tag_name : name
        self.notes = (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.pageURL = pageURL
        self.asset = Self.bestAsset(among: payload.assets ?? [])
        self.isFlaggedPrerelease = payload.prerelease ?? false
        self.publishedAt = payload.published_at
    }

    /// A `.dmg` if one was uploaded, else a `.zip`, else a `.pkg`. Checksums and notes attached
    /// alongside the build are skipped — offering someone a `.sha256` as "the download" is worse
    /// than offering them the release page.
    static func bestAsset(among assets: [Payload.AssetPayload]) -> Asset? {
        let preference = ["dmg", "zip", "pkg"]
        var best: (rank: Int, asset: Asset)?

        for candidate in assets {
            guard candidate.state == nil || candidate.state == "uploaded" else { continue }
            let ext = (candidate.name as NSString).pathExtension.lowercased()
            guard let rank = preference.firstIndex(of: ext) else { continue }
            guard let url = URL(string: candidate.browser_download_url) else { continue }
            let asset = Asset(name: candidate.name, url: url, byteCount: candidate.size ?? 0)
            if best == nil || rank < best!.rank {
                best = (rank, asset)
            }
        }
        return best?.asset
    }

    /// Only the fields used above. Anything else GitHub sends is ignored, so the feed growing new
    /// keys never breaks decoding.
    struct Payload: Decodable {
        let tag_name: String
        let html_url: String
        let name: String?
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let published_at: Date?
        let assets: [AssetPayload]?

        struct AssetPayload: Decodable {
            let name: String
            let browser_download_url: String
            let size: Int?
            let state: String?
        }
    }
}

// MARK: - Choosing

/// The "which release, and should we mention it" decisions, kept free of networking and of the
/// main actor so the test suite can exercise them directly.
public enum UpdateResolver {
    /// The highest version in the feed, not the most recently created one.
    public static func newest(in releases: [GitHubRelease], includePrereleases: Bool) -> GitHubRelease? {
        releases
            .filter { includePrereleases || !$0.isPrerelease }
            .max { $0.version < $1.version }
    }

    /// Whether a release is worth telling someone about.
    ///
    /// `skipped` is the tag of a version they pressed "Skip This Version" on. It suppresses only
    /// that exact version — a later one still gets through, which is the point of skipping rather
    /// than switching checks off.
    public static func isWorthOffering(
        _ release: GitHubRelease,
        current: AppVersion,
        skipping skipped: String = ""
    ) -> Bool {
        guard release.version > current else { return false }
        guard let skippedVersion = AppVersion(skipped) else { return true }
        return release.version != skippedVersion
    }
}
