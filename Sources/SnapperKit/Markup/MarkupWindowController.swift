import AppKit
import SwiftUI

/// Hosts the markup editor.
@MainActor
public final class MarkupWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsStore

    /// The edited image was saved somewhere; callers update their copy of the capture.
    public var onSaved: ((URL) -> Void)?

    public init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    public func open(_ result: CaptureResult) {
        close()

        let model = MarkupModel(base: result.image, scale: result.scale)
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
        window?.orderOut(nil)
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    public func windowWillClose(_ notification: Notification) {
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
