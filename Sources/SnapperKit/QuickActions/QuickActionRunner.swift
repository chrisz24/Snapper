import Foundation
import AppKit

/// Executes a quick action against a capture.
@MainActor
public final class QuickActionRunner {
    private let settings: SettingsStore

    /// The preview should go away (the action is done with it).
    public var onRequestDismiss: (() -> Void)?
    public var onRequestOCR: ((CaptureResult) -> Void)?
    public var onRequestMarkup: ((CaptureResult) -> Void)?
    /// The capture changed on disk (saved, moved) and callers holding it should update.
    public var onResultUpdated: ((CaptureResult) -> Void)?

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public func run(_ action: QuickAction, on result: CaptureResult) {
        switch action {
        case .copyImage:
            ClipboardWriter.write(result)
            HUD.shared.show("Copied to clipboard")
            onRequestDismiss?()

        case .saveAs:
            saveAs(result)

        case .saveToDefault:
            saveToDefaultFolder(result)

        case .ocr:
            onRequestOCR?(result)

        case .markup:
            onRequestMarkup?(result)

        case .revealInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
            onRequestDismiss?()

        case .openInPreview:
            NSWorkspace.shared.open(result.fileURL)
            onRequestDismiss?()

        case .delete:
            discard(result)

        case .dismiss:
            onRequestDismiss?()
        }
    }

    // MARK: - Saving

    private func saveAs(_ result: CaptureResult) {
        // An accessory-policy app has to come forward for a modal panel to be usable, so remember
        // where focus was and hand it back afterwards.
        let previousApp = NSWorkspace.shared.frontmostApplication

        NSApp.activate()

        let format = settings.imageFormat
        let panel = NSSavePanel()
        panel.title = "Save Screenshot"
        panel.directoryURL = settings.saveDirectory
        panel.nameFieldStringValue = suggestedName(for: result, format: format)
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.level = .modalPanel

        let response = panel.runModal()
        defer { previousApp?.activate() }

        guard response == .OK, let destination = panel.url else {
            return // cancelled; the preview stays up so another action is still possible
        }

        do {
            try write(result, to: destination, format: format)
            var updated = result
            updated.fileURL = destination
            updated.isTemporary = false
            onResultUpdated?(updated)
            HUD.shared.show("Saved to \(destination.deletingLastPathComponent().lastPathComponent)")
            onRequestDismiss?()
        } catch {
            HUD.shared.show("Could not save: \(error.localizedDescription)", style: .failure, duration: 3)
        }
    }

    private func saveToDefaultFolder(_ result: CaptureResult) {
        let format = settings.imageFormat
        let directory = settings.saveDirectory
        let destination = FilenameTemplate.uniqueURL(
            directory: directory,
            basename: (suggestedName(for: result, format: format) as NSString).deletingPathExtension,
            fileExtension: format.fileExtension
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try write(result, to: destination, format: format)
            var updated = result
            updated.fileURL = destination
            updated.isTemporary = false
            onResultUpdated?(updated)
            HUD.shared.show("Saved to \(directory.lastPathComponent)")
            onRequestDismiss?()
        } catch {
            HUD.shared.show("Could not save: \(error.localizedDescription)", style: .failure, duration: 3)
        }
    }

    private func write(_ result: CaptureResult, to destination: URL, format: ImageFormat) throws {
        if format == CaptureRequest.captureFormat, result.isTemporary {
            // Same format and the source is scratch — a move preserves the exact bytes and DPI.
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: result.fileURL, to: destination)
        } else {
            try ImageWriter.write(result.image, to: destination, format: format, scale: result.scale)
        }
    }

    private func suggestedName(for result: CaptureResult, format: ImageFormat) -> String {
        if !result.isTemporary {
            return result.fileURL.deletingPathExtension().lastPathComponent + "." + format.fileExtension
        }
        let context = FilenameContext(
            date: result.createdAt,
            pixelWidth: result.image.width,
            pixelHeight: result.image.height,
            modeName: CaptureCoordinator.modeName(for: result.mode)
        )
        return FilenameTemplate.render(settings.filenameTemplate, context: context) + "." + format.fileExtension
    }

    // MARK: - Deleting

    private func discard(_ result: CaptureResult) {
        if result.isTemporary {
            // Never saved anywhere the user can see — removing it outright is honest.
            try? FileManager.default.removeItem(at: result.fileURL)
            HUD.shared.show("Discarded", style: .info)
        } else {
            // It has a home the user chose, so it goes to the Trash where it can be recovered.
            NSWorkspace.shared.recycle([result.fileURL]) { _, _ in }
            HUD.shared.show("Moved to Trash", style: .info)
        }
        onRequestDismiss?()
    }
}
