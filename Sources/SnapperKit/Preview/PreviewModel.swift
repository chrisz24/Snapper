import AppKit
import SwiftUI

/// View state for the preview thumbnail.
@MainActor
final class PreviewModel: ObservableObject {
    @Published var image: NSImage
    /// 1 when freshly shown, 0 at expiry. Drives the countdown ring.
    @Published var progress: Double = 1
    @Published var showsCountdown: Bool = true
    @Published var isHovering: Bool = false
    @Published var isTextCapture: Bool = false
    @Published var hints: [Hint] = []
    @Published var dragURL: URL?

    var onHoverChange: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?

    struct Hint: Identifiable {
        let id = UUID()
        let shortcut: String
        let label: String
    }

    init(image: NSImage) {
        self.image = image
    }
}
