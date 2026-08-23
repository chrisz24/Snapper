import SwiftUI
import AppKit

struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    let thumbnailSize: CGSize

    private let cornerRadius: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            thumbnail
            if !model.hints.isEmpty {
                hintRow
            }
        }
        .padding(8)
        .onHover { hovering in
            model.isHovering = hovering
            model.onHoverChange?(hovering)
        }
    }

    // MARK: - Thumbnail

    /// The close button sits outside the image's own gesture area, in a ZStack above it, so a
    /// click on it is never swallowed by the tap-to-open or drag-out handlers underneath.
    private var thumbnail: some View {
        ZStack(alignment: .topLeading) {
            imageCard
            closeButton
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height, alignment: .topLeading)
    }

    private var imageCard: some View {
        Image(nsImage: model.image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                // A plain hairline rather than a glow: enough to separate the shot from a light
                // background without adding chrome of its own.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
            .overlay(alignment: .topTrailing) { countdown }
            .overlay(alignment: .bottomLeading) { badges }
            .contentShape(Rectangle())
            .onTapGesture { model.onClick?() }
            .modifier(DragOutModifier(url: model.dragURL))
    }

    /// Straddles the corner rather than sitting inside it, so it never covers the screenshot —
    /// the same placement macOS uses for its own removal badges.
    private var closeButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.black.opacity(0.72)))
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .contentShape(Circle())
            .onTapGesture { model.onClose?() }
            .opacity(model.isHovering ? 1 : 0.8)
            .animation(.easeOut(duration: 0.12), value: model.isHovering)
            .help("Dismiss this screenshot")
            .offset(x: -6, y: -6)
    }

    @ViewBuilder
    private var countdown: some View {
        if model.showsCountdown {
            ZStack {
                Circle().fill(.black.opacity(0.4))
                Circle()
                    .trim(from: 0, to: max(0, min(1, model.progress)))
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2.5)
            }
            .frame(width: 14, height: 14)
            .padding(5)
            .opacity(model.isHovering ? 0.3 : 0.9)
            .animation(.easeOut(duration: 0.12), value: model.isHovering)
        }
    }

    @ViewBuilder
    private var badges: some View {
        if model.isTextCapture {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(3)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(5)
        }
    }

    /// Always visible, not hover-gated. While these shortcuts are grabbed system-wide, showing
    /// which ones have been taken over is the difference between a feature and a surprise.
    ///
    /// Set on its own dark pill: the row previously sat as plain text directly on the desktop,
    /// where it was illegible against anything but a pale wallpaper.
    private var hintRow: some View {
        HStack(spacing: 8) {
            ForEach(model.hints) { hint in
                HStack(spacing: 3) {
                    Text(hint.shortcut)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    Text(hint.label)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.black.opacity(model.isHovering ? 0.75 : 0.6))
        )
        .animation(.easeOut(duration: 0.12), value: model.isHovering)
        .frame(maxWidth: thumbnailSize.width, alignment: .leading)
        .fixedSize()
    }
}

/// Dragging the thumbnail out drops the image file into Finder, Mail, chat apps, and so on.
private struct DragOutModifier: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url {
            content.onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        } else {
            content
        }
    }
}
