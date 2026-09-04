import Foundation
import CoreGraphics
import CoreImage
import AppKit

/// Draws the base image plus its annotations.
///
/// Display and export both go through here, so what appears on screen is exactly what lands in the
/// exported file — no second drawing path to drift out of sync.
public enum MarkupRenderer {

    public static func render(
        base: CGImage,
        elements: [MarkupElement],
        inProgress: MarkupElement?,
        cropRect: CGRect?,
        pixelated: CGImage?
    ) -> CGImage? {
        let width = base.width
        let height = base.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let full = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(base, in: full)

        // Redactions first: they replace pixels, so anything drawn on top stays visible.
        let all = elements + (inProgress.map { [$0] } ?? [])
        for element in all where element.tool == .redact {
            draw(redaction: element, in: context, pixelated: pixelated, bounds: full)
        }

        for element in all where element.tool != .redact && element.tool != .crop {
            draw(element, in: context)
        }

        // The crop marquee is guidance, not content: it never draws, it only trims the result.
        guard let rendered = context.makeImage() else { return nil }

        if let cropRect, cropRect.width > 1, cropRect.height > 1 {
            let clamped = cropRect.intersection(full).integral
            if clamped.width > 1, clamped.height > 1, let cropped = rendered.cropping(to: clamped) {
                return cropped
            }
        }
        return rendered
    }

    /// A pre-pixelated copy of the whole image; redactions are drawn by clipping to it.
    public static func pixelate(_ image: CGImage, blockSize: CGFloat = 14) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(blockSize, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }

    // MARK: - Element drawing

    private static func draw(redaction element: MarkupElement, in context: CGContext, pixelated: CGImage?, bounds: CGRect) {
        let rect = element.rect.integral
        guard rect.width > 1, rect.height > 1 else { return }

        context.saveGState()
        context.clip(to: rect)
        if let pixelated {
            context.draw(pixelated, in: bounds)
        } else {
            // No Core Image available: a solid block still removes the information.
            context.setFillColor(CGColor(gray: 0.1, alpha: 1))
            context.fill(rect)
        }
        context.restoreGState()
    }

    private static func draw(_ element: MarkupElement, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(element.lineWidth)
        context.setStrokeColor(element.color.cgColor)

        switch element.tool {
        case .rectangle:
            context.stroke(element.rect)

        case .ellipse:
            context.strokeEllipse(in: element.rect)

        case .line:
            guard let a = element.points.first, let b = element.points.last else { break }
            context.move(to: a)
            context.addLine(to: b)
            context.strokePath()

        case .arrow:
            guard let a = element.points.first, let b = element.points.last else { break }
            drawArrow(from: a, to: b, in: context, lineWidth: element.lineWidth, color: element.color.cgColor)

        case .freehand:
            guard element.points.count > 1 else { break }
            context.move(to: element.points[0])
            for point in element.points.dropFirst() { context.addLine(to: point) }
            context.strokePath()

        case .highlight:
            // Multiply keeps the text underneath readable, the way a real highlighter does.
            context.setBlendMode(.multiply)
            var colour = element.color
            colour.alpha = 0.38
            context.setFillColor(colour.cgColor)
            context.fill(element.rect)

        case .text:
            drawText(element, in: context)

        case .redact, .crop:
            break // handled elsewhere

        case .place:
            // Never reaches here: `.place` resolves to a real shape before anything is committed,
            // so an element carrying it would be a bug rather than something to draw.
            break
        }
    }

    /// A tapered arrow: nearly a point at the tail, thickening towards the head.
    ///
    /// The shaft is filled rather than stroked, because a stroke has one width along its whole
    /// length and cannot taper. Shaft and head are filled as two separate paths on purpose: in a
    /// single path their subpaths wind in opposite directions where they overlap, and the non-zero
    /// winding rule then cancels that region out, leaving a white notch across the arrow at larger
    /// line widths. Two fills of the same colour simply paint over each other.
    private static func drawArrow(from start: CGPoint, to end: CGPoint, in context: CGContext, lineWidth: CGFloat, color: CGColor) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(12, lineWidth * 4)
        let headAngle = CGFloat.pi / 7

        // Across the shaft, not along it.
        let normal = angle + .pi / 2
        let tailHalf = max(0.4, lineWidth * 0.16)
        let baseHalf = max(1.2, lineWidth * 0.62)

        // Where the shaft meets the head, pulled back so the two never leave a notch.
        let shaftEnd = CGPoint(
            x: end.x - cos(angle) * headLength * 0.62,
            y: end.y - sin(angle) * headLength * 0.62
        )

        func offset(_ point: CGPoint, by distance: CGFloat) -> CGPoint {
            CGPoint(x: point.x + cos(normal) * distance, y: point.y + sin(normal) * distance)
        }

        context.setFillColor(color)

        // The shaft, as a wedge from tail to head base.
        context.beginPath()
        context.move(to: offset(start, by: tailHalf))
        context.addLine(to: offset(shaftEnd, by: baseHalf))
        context.addLine(to: offset(shaftEnd, by: -baseHalf))
        context.addLine(to: offset(start, by: -tailHalf))
        context.closePath()
        context.fillPath()

        // The head, filled separately — see above.
        context.beginPath()
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        ))
        context.addLine(to: CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        ))
        context.closePath()
        context.fillPath()
    }

    private static func drawText(_ element: MarkupElement, in context: CGContext) {
        guard !element.text.isEmpty, let origin = element.points.first else { return }

        let fontSize = max(14, element.lineWidth * 5)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: element.color.nsColor,
        ]
        let string = NSAttributedString(string: element.text, attributes: attributes)

        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        string.draw(at: NSPoint(x: origin.x, y: origin.y))
        NSGraphicsContext.restoreGraphicsState()
    }
}
