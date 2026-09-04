import Foundation
import CoreGraphics
import AppKit

public enum MarkupTool: String, CaseIterable, Identifiable, Sendable {
    case arrow, rectangle, ellipse, line, freehand, highlight, redact, text, crop
    /// Places the shape you last drew, by clicking rather than dragging. Not a shape itself — it
    /// stands in for one, so what it commits is always a real arrow, box, ellipse and so on.
    case place

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .freehand: "Draw"
        case .highlight: "Highlight"
        case .redact: "Redact"
        case .text: "Text"
        case .crop: "Crop"
        case .place: "Place"
        }
    }

    public var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .freehand: "scribble"
        case .highlight: "highlighter"
        case .redact: "eye.slash"
        case .text: "textformat"
        case .crop: "crop"
        case .place: "cursorarrow.click"
        }
    }

    /// Tools defined by a start and end point rather than a free path.
    var isDragDefined: Bool { self != .freehand && self != .text }

    /// True for the stand-in tool, which draws whatever shape was last used rather than one of its
    /// own. Nothing is ever committed as `.place`; it resolves to a real shape first.
    public var placesLastShape: Bool { self == .place }

    /// "an arrow", "a rectangle" — so the interface can name a shape mid-sentence without a
    /// hand-written special case per tool.
    public var titleWithArticle: String {
        let name = title.lowercased()
        let article = "aeiou".contains(name.first ?? "x") ? "an" : "a"
        return "\(article) \(name)"
    }

    /// The shapes `.place` is allowed to stand in for — the ones defined by two points, which is
    /// what clicking a start and an end can express.
    public static var placeableShapes: [MarkupTool] {
        allCases.filter { $0.supportsClickAnchor && !$0.placesLastShape }
    }

    /// Tools that can be placed by clicking a start point and then clicking an end point, instead
    /// of holding the button down. Crop is excluded on purpose: its preview and its committed value
    /// are the same piece of state, so a half-placed crop would be indistinguishable from a real one.
    public var supportsClickAnchor: Bool { isDragDefined && self != .crop }
}

/// Codable colour, so markup state can be persisted later without dragging NSColor along.
public struct MarkupColor: Equatable, Codable, Sendable {
    public var red: Double, green: Double, blue: Double, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public static let red = MarkupColor(red: 1, green: 0.23, blue: 0.19)
    public static let yellow = MarkupColor(red: 1, green: 0.8, blue: 0)
    public static let green = MarkupColor(red: 0.2, green: 0.78, blue: 0.35)
    public static let blue = MarkupColor(red: 0, green: 0.48, blue: 1)
    public static let black = MarkupColor(red: 0, green: 0, blue: 0)
    public static let white = MarkupColor(red: 1, green: 1, blue: 1)

    public static let palette: [MarkupColor] = [.red, .yellow, .green, .blue, .black, .white]
}

/// One annotation, in image pixel coordinates so export is exact at any zoom.
public struct MarkupElement: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var tool: MarkupTool
    public var points: [CGPoint]
    public var color: MarkupColor
    public var lineWidth: CGFloat
    public var text: String

    public init(
        id: UUID = UUID(),
        tool: MarkupTool,
        points: [CGPoint],
        color: MarkupColor,
        lineWidth: CGFloat,
        text: String = ""
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
    }

    /// Bounding rect for the drag-defined tools.
    public var rect: CGRect {
        guard let first = points.first, let last = points.last else { return .zero }
        return CGRect(
            x: min(first.x, last.x),
            y: min(first.y, last.y),
            width: abs(last.x - first.x),
            height: abs(last.y - first.y)
        )
    }
}

@MainActor
public final class MarkupModel: ObservableObject {
    @Published public var elements: [MarkupElement] = []
    @Published public var tool: MarkupTool = .arrow {
        didSet {
            // A half-placed shape belongs to the tool that started it.
            guard tool != oldValue else { return }
            cancelAnchor()
        }
    }
    @Published public var color: MarkupColor = .red
    @Published public var lineWidth: CGFloat = 4
    @Published public var inProgress: MarkupElement?
    @Published public var cropRect: CGRect?
    /// The shape `.place` stands in for: whatever was last drawn with a real shape tool.
    @Published public var lastShape: MarkupTool = .arrow
    /// Where a click-placed shape starts, while it waits for the click that finishes it.
    @Published public var anchor: CGPoint?
    /// Set while a text element is being typed.
    @Published public var pendingTextOrigin: CGPoint?
    @Published public var pendingText: String = ""

    public let base: CGImage
    public let scale: CGFloat

    private var pixelatedCache: CGImage?
    private var hasPixelated = false
    private var undoStack: [[MarkupElement]] = []
    private var redoStack: [[MarkupElement]] = []

    public init(base: CGImage, scale: CGFloat) {
        self.base = base
        self.scale = scale
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public var imageSize: CGSize {
        CGSize(width: base.width, height: base.height)
    }

    /// The shape actually being drawn. `.place` is a stand-in and resolves to `lastShape`; every
    /// other tool is itself. Everything that draws or commits goes through this, so no element is
    /// ever created carrying `.place`.
    public var effectiveTool: MarkupTool {
        tool.placesLastShape ? lastShape : tool
    }

    /// Anything worth carrying back to the capture.
    public var hasEdits: Bool { !elements.isEmpty || cropRect != nil }

    /// Click once to fix where the shape starts, move, then click again to finish it — for placing
    /// an arrow's tail exactly without holding the button down. Dragging still works as before.
    public func handleClick(at point: CGPoint) {
        guard tool.supportsClickAnchor else { return }
        let shape = effectiveTool

        guard let start = anchor else {
            anchor = point
            inProgress = MarkupElement(tool: shape, points: [point, point],
                                       color: color, lineWidth: lineWidth)
            return
        }

        let element = MarkupElement(tool: shape, points: [start, point],
                                    color: color, lineWidth: lineWidth)
        guard element.rect.width >= 3 || element.rect.height >= 3 else {
            // Clicking the same spot again means "never mind", rather than committing a shape too
            // small to see or to select afterwards.
            cancelAnchor()
            return
        }
        commit(element)
        anchor = nil
    }

    /// Follows the pointer between the two clicks, so the shape is previewed before it is placed.
    public func moveAnchoredEnd(to point: CGPoint) {
        guard let anchor, tool.supportsClickAnchor else { return }
        inProgress = MarkupElement(tool: effectiveTool, points: [anchor, point],
                                   color: color, lineWidth: lineWidth)
    }

    public func cancelAnchor() {
        guard anchor != nil else { return }
        anchor = nil
        inProgress = nil
    }

    /// A pre-pixelated copy of the base image, for drawing redactions. Computed once, here rather
    /// than in the editor, so the window controller can flatten on close without the view's help.
    public var pixelated: CGImage? {
        if !hasPixelated {
            pixelatedCache = MarkupRenderer.pixelate(base)
            hasPixelated = true
        }
        return pixelatedCache
    }

    /// The image with every annotation drawn in and the crop applied.
    public func flattened() -> CGImage? {
        MarkupRenderer.render(base: base, elements: elements, inProgress: nil,
                              cropRect: cropRect, pixelated: pixelated)
    }

    public func commit(_ element: MarkupElement) {
        pushUndo()
        elements.append(element)
        inProgress = nil
        // Recorded from the element rather than from `tool`, so a shape drawn *through* `.place`
        // keeps the memory pointing at a real shape instead of at the stand-in.
        if MarkupTool.placeableShapes.contains(element.tool) {
            lastShape = element.tool
        }
    }

    public func setCrop(_ rect: CGRect?) {
        pushUndo()
        cropRect = rect
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(elements)
        elements = previous
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(elements)
        elements = next
    }

    public func clearAll() {
        pushUndo()
        elements = []
        cropRect = nil
    }

    private func pushUndo() {
        undoStack.append(elements)
        redoStack.removeAll()
        if undoStack.count > 100 { undoStack.removeFirst() }
    }
}
