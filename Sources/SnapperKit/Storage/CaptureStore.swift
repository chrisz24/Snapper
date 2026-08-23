import Foundation
import AppKit

public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var fileURL: URL
    public var thumbnailURL: URL?
    public var createdAt: Date
    public var modeName: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var scale: CGFloat

    public var displayName: String { fileURL.lastPathComponent }

    public var dimensionsLabel: String {
        "\(Int(CGFloat(pixelWidth) / scale)) × \(Int(CGFloat(pixelHeight) / scale))"
    }
}

/// Keeps recent captures reachable after their preview has gone.
@MainActor
public final class CaptureStore: ObservableObject {
    public static let shared = CaptureStore()

    @Published public private(set) var entries: [HistoryEntry] = []

    private let indexURL: URL
    private let thumbnailDirectory: URL
    private let thumbnailMaxEdge: CGFloat = 320

    public init(directory: URL = AppInfo.supportDirectory) {
        self.indexURL = directory.appendingPathComponent("history.json")
        self.thumbnailDirectory = directory.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Recording

    public func record(_ result: CaptureResult, limit: Int) {
        // Captures still sitting in scratch are recorded too. With automatic saving off they are
        // the normal case, and leaving them out would make every unsaved capture unreachable the
        // moment its preview expired. `ScratchCleaner` ages them out, and `load()` drops entries
        // whose files have gone, so the index cannot go stale.
        let thumbnailURL = writeThumbnail(for: result)
        let entry = HistoryEntry(
            id: UUID(),
            fileURL: result.fileURL,
            thumbnailURL: thumbnailURL,
            createdAt: result.createdAt,
            modeName: CaptureCoordinator.modeName(for: result.mode),
            pixelWidth: result.image.width,
            pixelHeight: result.image.height,
            scale: result.scale
        )

        entries.removeAll { $0.fileURL == result.fileURL }
        entries.insert(entry, at: 0)
        prune(to: limit)
        save()
    }

    /// Follows a capture that moved, so "Save As…" does not orphan its history entry.
    public func updateLocation(from oldURL: URL, to newURL: URL) {
        guard let index = entries.firstIndex(where: { $0.fileURL == oldURL }) else { return }
        entries[index].fileURL = newURL
        save()
    }

    public func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        if let thumbnailURL = entry.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
        save()
    }

    public func clear() {
        for entry in entries {
            if let thumbnailURL = entry.thumbnailURL {
                try? FileManager.default.removeItem(at: thumbnailURL)
            }
        }
        entries = []
        save()
    }

    /// Rebuilds a capture from a history entry, re-reading the file from disk.
    public func load(_ entry: HistoryEntry) -> CaptureResult? {
        guard FileManager.default.fileExists(atPath: entry.fileURL.path),
              let (image, scale) = try? ScreencaptureCLIEngine.loadImage(at: entry.fileURL)
        else { return nil }

        return CaptureResult(
            fileURL: entry.fileURL,
            image: image,
            scale: scale,
            mode: .region,
            createdAt: entry.createdAt,
            isTemporary: false
        )
    }

    public func thumbnailImage(for entry: HistoryEntry) -> NSImage? {
        guard let url = entry.thumbnailURL else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Persistence

    private func prune(to limit: Int) {
        guard entries.count > limit, limit > 0 else { return }
        let dropped = entries.suffix(from: limit)
        for entry in dropped {
            if let thumbnailURL = entry.thumbnailURL {
                try? FileManager.default.removeItem(at: thumbnailURL)
            }
        }
        entries = Array(entries.prefix(limit))
    }

    private func writeThumbnail(for result: CaptureResult) -> URL? {
        let longestEdge = CGFloat(max(result.image.width, result.image.height))
        guard longestEdge > 0 else { return nil }

        let factor = min(1, thumbnailMaxEdge / longestEdge)
        let image: CGImage
        if factor < 1, let scaled = TextRecognizer.upscale(result.image, by: factor) {
            image = scaled
        } else {
            image = result.image
        }

        let url = thumbnailDirectory.appendingPathComponent("\(UUID().uuidString).png")
        guard let data = ImageWriter.pngData(image) else { return nil }
        try? data.write(to: url)
        return url
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        // Files the user deleted or moved elsewhere should not linger as dead menu items.
        entries = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        if entries.count != decoded.count { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
