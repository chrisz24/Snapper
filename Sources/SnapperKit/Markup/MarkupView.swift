import SwiftUI
import AppKit

struct MarkupView: View {
    @ObservedObject var model: MarkupModel
    var onCopy: (CGImage) -> Void
    var onSave: (CGImage) -> Void
    var onClose: () -> Void

    /// Pixelating the whole image once is far cheaper than doing it per redaction per frame.
    @State private var pixelated: CGImage?
    @State private var rendered: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
            Divider()
            footer
        }
        .onAppear {
            pixelated = MarkupRenderer.pixelate(model.base)
            rerender()
        }
        .onChange(of: model.elements) { _, _ in rerender() }
        .onChange(of: model.inProgress) { _, _ in rerender() }
        .onChange(of: model.cropRect) { _, _ in rerender() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            ForEach(MarkupTool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 26, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(model.tool == tool ? Color.accentColor.opacity(0.22) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tool.title)
            }

            Divider().frame(height: 18)

            ForEach(Array(MarkupColor.palette.enumerated()), id: \.offset) { _, colour in
                Button {
                    model.color = colour
                } label: {
                    Circle()
                        .fill(Color(nsColor: colour.nsColor))
                        .frame(width: 15, height: 15)
                        .overlay(
                            Circle().strokeBorder(
                                model.color == colour ? Color.primary : Color.primary.opacity(0.25),
                                lineWidth: model.color == colour ? 2 : 0.5
                            )
                        )
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 18)

            Slider(value: $model.lineWidth, in: 1...24).frame(width: 90)

            Spacer()

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            let fitted = fittedRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)

                if let rendered {
                    Image(nsImage: NSImage(cgImage: rendered, size: .zero))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                }

                if let cropRect = model.cropRect {
                    cropOverlay(cropRect, fitted: fitted)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(fitted: fitted))
            .onTapGesture { location in
                guard model.tool == .text else { return }
                model.pendingTextOrigin = imagePoint(from: location, fitted: fitted)
                model.pendingText = ""
            }
            .overlay(alignment: .topLeading) {
                if let origin = model.pendingTextOrigin {
                    textEntry(at: origin, fitted: fitted)
                }
            }
        }
    }

    private func cropOverlay(_ rect: CGRect, fitted: CGRect) -> some View {
        let view = viewRect(from: rect, fitted: fitted)
        return Rectangle()
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            .frame(width: view.width, height: view.height)
            .offset(x: view.minX, y: view.minY)
            .allowsHitTesting(false)
    }

    private func textEntry(at origin: CGPoint, fitted: CGRect) -> some View {
        let view = viewPoint(from: origin, fitted: fitted)
        return TextField("Text", text: $model.pendingText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            .offset(x: view.x, y: view.y - 12)
            .onSubmit {
                if !model.pendingText.isEmpty {
                    model.commit(MarkupElement(
                        tool: .text,
                        points: [origin],
                        color: model.color,
                        lineWidth: model.lineWidth,
                        text: model.pendingText
                    ))
                }
                model.pendingTextOrigin = nil
                model.pendingText = ""
            }
    }

    private func dragGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard model.tool != .text else { return }
                let start = imagePoint(from: value.startLocation, fitted: fitted)
                let current = imagePoint(from: value.location, fitted: fitted)

                if model.tool == .crop {
                    model.cropRect = CGRect(
                        x: min(start.x, current.x), y: min(start.y, current.y),
                        width: abs(current.x - start.x), height: abs(current.y - start.y)
                    )
                    return
                }

                if model.tool == .freehand {
                    var points = model.inProgress?.points ?? [start]
                    points.append(current)
                    model.inProgress = MarkupElement(
                        tool: .freehand, points: points,
                        color: model.color, lineWidth: model.lineWidth
                    )
                } else {
                    model.inProgress = MarkupElement(
                        tool: model.tool, points: [start, current],
                        color: model.color, lineWidth: model.lineWidth
                    )
                }
            }
            .onEnded { _ in
                if model.tool == .crop {
                    if let rect = model.cropRect, rect.width > 4, rect.height > 4 {
                        model.setCrop(rect)
                    } else {
                        model.cropRect = nil
                    }
                    return
                }
                guard let element = model.inProgress else { return }
                let isDegenerate = element.tool.isDragDefined
                    && element.rect.width < 3 && element.rect.height < 3
                if isDegenerate {
                    model.inProgress = nil
                } else {
                    model.commit(element)
                }
            }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Clear") { model.clearAll() }
                .disabled(model.elements.isEmpty && model.cropRect == nil)
            if model.cropRect != nil {
                Button("Remove Crop") { model.setCrop(nil) }
            }
            Spacer()
            Text("\(model.elements.count) annotation\(model.elements.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
            Button("Copy") {
                if let image = flattened() { onCopy(image) }
            }
            .keyboardShortcut("c", modifiers: .command)
            Button("Save…") {
                if let image = flattened() { onSave(image) }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Rendering

    private func rerender() {
        rendered = MarkupRenderer.render(
            base: model.base,
            elements: model.elements,
            inProgress: model.inProgress,
            cropRect: nil, // the crop is previewed as a marquee, applied only on export
            pixelated: pixelated
        )
    }

    private func flattened() -> CGImage? {
        MarkupRenderer.render(
            base: model.base,
            elements: model.elements,
            inProgress: nil,
            cropRect: model.cropRect,
            pixelated: pixelated
        )
    }

    // MARK: - Coordinate mapping

    /// The image is letterboxed inside the canvas; everything maps through this rect.
    private func fittedRect(in size: CGSize) -> CGRect {
        let image = model.imageSize
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = min(size.width / image.width, size.height / image.height, 1)
        let width = image.width * scale
        let height = image.height * scale
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// View coordinates are top-left origin; Core Graphics image space is bottom-left.
    private func imagePoint(from viewPoint: CGPoint, fitted: CGRect) -> CGPoint {
        guard fitted.width > 0, fitted.height > 0 else { return .zero }
        let relativeX = (viewPoint.x - fitted.minX) / fitted.width
        let relativeY = (viewPoint.y - fitted.minY) / fitted.height
        return CGPoint(
            x: relativeX * model.imageSize.width,
            y: (1 - relativeY) * model.imageSize.height
        )
    }

    private func viewPoint(from imagePoint: CGPoint, fitted: CGRect) -> CGPoint {
        CGPoint(
            x: fitted.minX + (imagePoint.x / model.imageSize.width) * fitted.width,
            y: fitted.minY + (1 - imagePoint.y / model.imageSize.height) * fitted.height
        )
    }

    private func viewRect(from imageRect: CGRect, fitted: CGRect) -> CGRect {
        let topLeft = viewPoint(from: CGPoint(x: imageRect.minX, y: imageRect.maxY), fitted: fitted)
        let bottomRight = viewPoint(from: CGPoint(x: imageRect.maxX, y: imageRect.minY), fitted: fitted)
        return CGRect(
            x: topLeft.x, y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }
}
