import Foundation

/// Keeps the scratch folder from growing without limit.
///
/// With automatic saving off — the default — captures stay in scratch unless the user explicitly
/// saves one. Nothing else would ever remove them, so this prunes anything old enough that it is
/// clearly no longer wanted. `CaptureStore` drops history entries whose files have gone, so the
/// two stay consistent without needing to coordinate.
public enum ScratchCleaner {
    public static let defaultMaxAge: TimeInterval = 7 * 24 * 60 * 60

    @discardableResult
    public static func prune(in directory: URL? = nil,
                             olderThan maxAge: TimeInterval = defaultMaxAge,
                             now: Date = Date()) -> Int {
        let directory = directory ?? AppInfo.scratchDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var removed = 0
        for url in entries {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, now.timeIntervalSince(modified) > maxAge else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }
}
