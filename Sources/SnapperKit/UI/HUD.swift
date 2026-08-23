import AppKit
import SwiftUI

/// Small transient toast.
///
/// Used in place of `UNUserNotificationCenter`, which is unreliable for ad-hoc-signed apps
/// distributed outside the App Store — and which would put confirmations behind a permission
/// prompt for a message that only needs to live for a second.
@MainActor
public final class HUD {
    public static let shared = HUD()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    public enum Style {
        case success, failure, info

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .failure: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: .green
            case .failure: .orange
            case .info: .secondary
            }
        }
    }

    public func show(_ message: String, style: Style = .success, duration: TimeInterval = 1.6) {
        dismissTask?.cancel()
        hideImmediately()

        let content = HUDView(message: message, style: style)
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false

        if let screen = DisplayLocator.screenUnderPointer {
            let visible = screen.visibleFrame
            let size = hosting.fittingSize
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + 120
            ))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.hideImmediately()
        }
    }

    private func hideImmediately() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct HUDView: View {
    let message: String
    let style: HUD.Style

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: style.symbol)
                .foregroundStyle(style.tint)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .fixedSize()
    }
}
