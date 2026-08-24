import AppKit

/// A small panel shown while an update downloads and is checked.
///
/// A panel rather than an `NSAlert` accessory view: an alert runs a modal loop, which would block
/// the very async work whose progress it is meant to be showing.
@MainActor
public final class UpdateProgressWindow: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var bar: NSProgressIndicator?
    private var label: NSTextField?
    private var detail: NSTextField?

    /// Called by the Cancel button and by closing the panel.
    public var onCancel: (() -> Void)?

    public func show(title: String) {
        if panel != nil { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 132),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Software Update"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.frame = NSRect(x: 20, y: 92, width: 380, height: 20)

        let progress = NSProgressIndicator(frame: NSRect(x: 20, y: 66, width: 380, height: 16))
        progress.style = .bar
        progress.isIndeterminate = true
        progress.minValue = 0
        progress.maxValue = 1
        progress.startAnimation(nil)

        let subtitle = NSTextField(labelWithString: "Starting…")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 20, y: 44, width: 380, height: 16)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 320, y: 12, width: 84, height: 24)

        for view in [heading, progress, subtitle, cancel] as [NSView] {
            panel.contentView?.addSubview(view)
        }

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
        self.bar = progress
        self.label = heading
        self.detail = subtitle
    }

    public func update(_ progress: UpdateInstaller.Progress) {
        switch progress {
        case .downloading(let fraction, let received, let expected):
            if expected > 0 {
                bar?.isIndeterminate = false
                bar?.doubleValue = fraction
                detail?.stringValue = "\(Self.size(received)) of \(Self.size(expected))"
            } else {
                bar?.isIndeterminate = true
                detail?.stringValue = Self.size(received)
            }
        case .verifying:
            bar?.isIndeterminate = true
            bar?.startAnimation(nil)
            detail?.stringValue = "Checking Apple's signature…"
        }
    }

    public func close() {
        // Cleared first so windowWillClose does not read this as the user cancelling.
        onCancel = nil
        panel?.close()
        panel = nil
        bar = nil
    }

    @objc private func cancelPressed() {
        let cancel = onCancel
        close()
        cancel?()
    }

    public func windowWillClose(_ notification: Notification) {
        onCancel?()
        panel = nil
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
