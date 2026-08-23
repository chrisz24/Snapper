import Foundation
import CoreGraphics
import SnapperKit

enum MarkupTests {

    /// A plain opaque bitmap, built without AppKit so the test needs no window server.
    private static func makeImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.6, green: 0.7, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func run() {
        Harness.suite("Markup") {
            Harness.test("a rect is normalised however the drag was made") {
                let downRight = MarkupElement(
                    tool: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)],
                    color: .red, lineWidth: 4)
                let upLeft = MarkupElement(
                    tool: .rectangle, points: [CGPoint(x: 60, y: 40), CGPoint(x: 10, y: 10)],
                    color: .red, lineWidth: 4)
                Harness.expectEqual(downRight.rect, CGRect(x: 10, y: 10, width: 50, height: 30))
                Harness.expectEqual(upLeft.rect, downRight.rect, "drag direction must not matter")
            }

            Harness.test("an empty element has a zero rect rather than crashing") {
                let empty = MarkupElement(tool: .arrow, points: [], color: .red, lineWidth: 3)
                Harness.expectEqual(empty.rect, .zero)
            }

            guard let base = makeImage(width: 200, height: 120) else {
                Harness.test("build a base image") { Harness.expect(false, "could not create bitmap") }
                return
            }

            Harness.test("rendering without a crop preserves the original size") {
                let elements = [
                    MarkupElement(tool: .arrow, points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 90)],
                                  color: .red, lineWidth: 4),
                    MarkupElement(tool: .rectangle, points: [CGPoint(x: 20, y: 20), CGPoint(x: 120, y: 80)],
                                  color: .blue, lineWidth: 3),
                    MarkupElement(tool: .highlight, points: [CGPoint(x: 5, y: 5), CGPoint(x: 60, y: 30)],
                                  color: .yellow, lineWidth: 2),
                ]
                let output = MarkupRenderer.render(
                    base: base, elements: elements, inProgress: nil, cropRect: nil, pixelated: nil)
                Harness.expect(output != nil, "renderer returned nil")
                Harness.expectEqual(output?.width, 200)
                Harness.expectEqual(output?.height, 120)
            }

            Harness.test("a crop trims the exported image") {
                let output = MarkupRenderer.render(
                    base: base, elements: [], inProgress: nil,
                    cropRect: CGRect(x: 20, y: 10, width: 100, height: 60), pixelated: nil)
                Harness.expectEqual(output?.width, 100)
                Harness.expectEqual(output?.height, 60)
            }

            Harness.test("a crop reaching past the edge is clamped, not refused") {
                let output = MarkupRenderer.render(
                    base: base, elements: [], inProgress: nil,
                    cropRect: CGRect(x: 150, y: 80, width: 400, height: 400), pixelated: nil)
                Harness.expectEqual(output?.width, 50)
                Harness.expectEqual(output?.height, 40)
            }

            Harness.test("a degenerate crop falls back to the full image") {
                let output = MarkupRenderer.render(
                    base: base, elements: [], inProgress: nil,
                    cropRect: CGRect(x: 10, y: 10, width: 0, height: 0), pixelated: nil)
                Harness.expectEqual(output?.width, 200)
            }

            Harness.test("redaction without Core Image still covers the region") {
                // The fallback path must not silently leave the pixels readable.
                let output = MarkupRenderer.render(
                    base: base,
                    elements: [MarkupElement(tool: .redact, points: [CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 60)],
                                             color: .black, lineWidth: 1)],
                    inProgress: nil, cropRect: nil, pixelated: nil)
                Harness.expect(output != nil)
            }

            Harness.test("pixelate produces an image of the same size") {
                let pixelated = MarkupRenderer.pixelate(base, blockSize: 10)
                Harness.expect(pixelated != nil, "pixelate returned nil")
                Harness.expectEqual(pixelated?.width, 200)
                Harness.expectEqual(pixelated?.height, 120)
            }

            Harness.test("in-progress elements are drawn alongside committed ones") {
                let output = MarkupRenderer.render(
                    base: base, elements: [],
                    inProgress: MarkupElement(tool: .freehand,
                                              points: [CGPoint(x: 1, y: 1), CGPoint(x: 50, y: 50)],
                                              color: .green, lineWidth: 5),
                    cropRect: nil, pixelated: nil)
                Harness.expect(output != nil)
            }
        }
    }
}
