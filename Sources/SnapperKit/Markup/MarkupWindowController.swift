import AppKit
import SwiftUI

/// Hosts the markup editor.
@MainActor
public final class MarkupWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore

    /// The edited image was saved somewhere; callers update their copy of the capture.
    public var onSaved: ((URL) -> Void)?

    /// The editor closed with annotations on the image, so the working capture now *is* the edited
    /// one. Closing used to throw the edits away, which made markup a dead end unless you exported
    /// from inside it — the capture you carried on with was still the unmarked original.
    public var onEdited: ((CaptureResult) -> Void)?

    /// What is being edited, so closing by any route can finish the job.
    private var session: (model: MarkupModel, result: CaptureResult)?

    public init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    /// The live editor window. Exposed for `--markup-demo`, the only way to look at this window
    /// without first taking a real capture.
    public var debugWindow: NSWindow? { window }

    /// The live editor's model, so `--markup-demo --samples` can seed annotations.
    public var debugModel: MarkupModel? { session?.model }

    public func open(_ result: CaptureResult) {
        close()

        let model = MarkupModel(base: result.image, scale: result.scale)
        // Pick up where the last session left off. The shape is restored before the tool, so a
        // session reopening on Place already knows what Place draws.
        model.lastShape = MarkupTool(rawValue: settings.lastMarkupShape)
            .flatMap { MarkupTool.placeableShapes.contains($0) ? $0 : nil } ?? .arrow
        model.tool = MarkupTool(rawValue: settings.lastMarkupTool) ?? .arrow
        session = (model, result)
        let view = MarkupView(
            model: model,
            onCopy: { [weak self] image in
                self?.copy(image, scale: result.scale)
            },
            onSave: { [weak self] image in
                self?.save(image, basedOn: result)
            },
            onClose: { [weak self] in self?.close() }
        )

        let size = fittingSize(for: result)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markup — \(result.fileURL.lastPathComponent)"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.minSize = NSSize(width: 620, height: 480)
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func close() {
        finishSession()
        window?.orderOut(nil)
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// Writes the annotations into the capture being edited and remembers the tool, whichever way
    /// the editor was closed — the button, the window's own close box, or an export.
    private func finishSession() {
        guard let (model, result) = session else { return }
        session = nil
        settings.lastMarkupTool = model.tool.rawValue
        settings.lastMarkupShape = model.lastShape.rawValue

        guard model.hasEdits, let edited = model.flattened() else { return }

        // A capture still in scratch is a working copy, so the edits replace it. One the user has
        // already saved somewhere is theirs: that file is left exactly as it is and the edited
        // version becomes a new scratch capture instead.
        let destination = result.isTemporary
            ? result.fileURL
            : AppInfo.scratchDirectory
                .appendingPathComponent(result.fileURL.deletingPathExtension().lastPathComponent
                                        + " marked up")
                .appendingPathExtension(result.fileURL.pathExtension)

        do {
            try ImageWriter.write(edited, to: destination, format: settings.imageFormat,
                                  scale: result.scale)
        } catch {
            HUD.shared.show("Could not keep the markup: \(error.localizedDescription)",
                            style: .failure, duration: 3)
            return
        }

        var updated = result
        updated.fileURL = destination
        updated.image = edited
        // Temporary either way: the edits either replaced a scratch file, or went into a new one
        // beside the saved original. Neither is a file the user has chosen a home for yet.
        updated.isTemporary = true
        onEdited?(updated)
    }

    public func windowWillClose(_ notification: Notification) {
        finishSession()
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Export

    private func copy(_ image: CGImage, scale: CGFloat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let data = ImageWriter.pngData(image, scale: scale) {
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
            pasteboard.writeObjects([item])
        }
        HUD.shared.show("Copied with markup")
        close()
    }

    private func save(_ image: CGImage, basedOn result: CaptureResult) {
        let format = settings.imageFormat
        let panel = NSSavePanel()
        panel.title = "Save Marked-Up Screenshot"
        panel.directoryURL = settings.saveDirectory
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true

        let stem = result.fileURL.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(stem) marked up.\(format.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ImageWriter.write(image, to: url, format: format, scale: result.scale)
            onSaved?(url)
            HUD.shared.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
            close()
        } catch {
            HUD.shared.show("Could not save: \(error.localizedDescription)", style: .failure, duration: 3)
        }
    }

    private func fittingSize(for result: CaptureResult) -> NSSize {
        let point = result.pointSize
        let maxWidth: CGFloat = 1100
        let maxHeight: CGFloat = 780
        let scale = min(maxWidth / max(point.width, 1), maxHeight / max(point.height, 1), 1)
        return NSSize(
            width: max(700, point.width * scale + 40),
            height: max(520, point.height * scale + 110)
        )
    }
}
