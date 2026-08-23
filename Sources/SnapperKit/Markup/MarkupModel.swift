import Foundation
import CoreGraphics
import AppKit

public enum MarkupTool: String, CaseIterable, Identifiable, Sendable {
    case arrow, rectangle, ellipse, line, freehand, highlight, redact, text, crop

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
        }
    }

    /// Tools defined by a start and end point rather than a free path.
    var isDragDefined: Bool { self != .freehand && self != .text }
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
    @Published public var tool: MarkupTool = .arrow
    @Published public var color: MarkupColor = .red
    @Published public var lineWidth: CGFloat = 4
    @Published public var inProgress: MarkupElement?
    @Published public var cropRect: CGRect?
    /// Set while a text element is being typed.
    @Published public var pendingTextOrigin: CGPoint?
    @Published public var pendingText: String = ""

    public let base: CGImage
    public let scale: CGFloat

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

    public func commit(_ element: MarkupElement) {
        pushUndo()
        elements.append(element)
        inProgress = nil
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
