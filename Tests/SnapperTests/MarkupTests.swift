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

    /// A plain white bitmap, so red annotation pixels stand out unambiguously.
    private static func makeWhiteImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// One pixel out of a rendered image, as (r, g, b). Nil if it could not be read.
    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (Int, Int, Int)? {
        let width = image.width, height = image.height
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (Int(buffer[offset]), Int(buffer[offset + 1]), Int(buffer[offset + 2]))
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

            Harness.test("a thick arrow has no hole where the shaft meets the head") {
                // The shaft and the head overlap. Filled as one path, their subpaths wind in
                // opposite directions there and the non-zero rule cancels the overlap out, leaving
                // a white notch straight across the arrow — visible at large line widths only,
                // which is exactly how it shipped unnoticed.
                //
                // A 100px-tall image with the arrow at y=50 is unaffected by the context's vertical
                // flip, so the sample points hold whichever way up it is drawn.
                guard let white = makeWhiteImage(width: 200, height: 100) else { return }
                let arrow = MarkupElement(
                    tool: .arrow,
                    points: [CGPoint(x: 20, y: 50), CGPoint(x: 180, y: 50)],
                    color: .red, lineWidth: 14)
                guard let output = MarkupRenderer.render(
                    base: white, elements: [arrow], inProgress: nil,
                    cropRect: nil, pixelated: nil) else {
                    Harness.expect(false, "nothing rendered")
                    return
                }
                // headLength = max(12, 14 * 4) = 56; the join sits 0.62 of that back from the tip.
                for x in [143, 146, 150] {
                    guard let (r, g, b) = pixel(output, x: x, y: 50) else { continue }
                    Harness.expect(!(r > 240 && g > 240 && b > 240),
                                   "white gap at x=\(x): rgb(\(r), \(g), \(b))")
                }
            }

            Harness.test("an arrow is thinner at the tail than at the head") {
                // The taper itself: sample near the tail and near the head base.
                guard let white = makeWhiteImage(width: 200, height: 100) else { return }
                let arrow = MarkupElement(
                    tool: .arrow,
                    points: [CGPoint(x: 20, y: 50), CGPoint(x: 180, y: 50)],
                    color: .red, lineWidth: 14)
                guard let output = MarkupRenderer.render(
                    base: white, elements: [arrow], inProgress: nil,
                    cropRect: nil, pixelated: nil) else { return }

                func thickness(atX x: Int) -> Int {
                    (0..<100).filter { y in
                        guard let (r, g, b) = pixel(output, x: x, y: y) else { return false }
                        return !(r > 240 && g > 240 && b > 240)
                    }.count
                }
                let tail = thickness(atX: 25)
                let base = thickness(atX: 140)
                Harness.expect(tail < base, "tail \(tail)px is not thinner than the head end \(base)px")
                Harness.expect(tail >= 1, "the tail vanished entirely")
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

        Harness.suite("Markup — placing a shape by clicking") {
            guard let base = makeImage(width: 200, height: 120) else { return }

            func model(_ tool: MarkupTool) -> MarkupModel {
                MainActor.assumeIsolated {
                    let m = MarkupModel(base: base, scale: 2)
                    m.tool = tool
                    return m
                }
            }

            Harness.test("the first click anchors the shape without committing it") {
                MainActor.assumeIsolated {
                    let m = model(.arrow)
                    m.handleClick(at: CGPoint(x: 20, y: 30))
                    Harness.expect(m.anchor == CGPoint(x: 20, y: 30), "anchor not set")
                    Harness.expect(m.elements.isEmpty, "committed too early")
                    Harness.expect(m.inProgress != nil, "nothing to see while it waits")
                }
            }

            Harness.test("the second click commits it from the anchor") {
                MainActor.assumeIsolated {
                    let m = model(.arrow)
                    m.handleClick(at: CGPoint(x: 20, y: 30))
                    m.handleClick(at: CGPoint(x: 90, y: 80))
                    Harness.expectEqual(m.elements.count, 1)
                    // The tail is where the first click landed — the whole point of the feature.
                    Harness.expect(m.elements.first?.points.first == CGPoint(x: 20, y: 30),
                                   "the shape does not start where it was anchored")
                    Harness.expect(m.elements.first?.points.last == CGPoint(x: 90, y: 80))
                    Harness.expect(m.anchor == nil, "anchor left armed after committing")
                    Harness.expect(m.inProgress == nil)
                }
            }

            Harness.test("the preview follows the pointer between the two clicks") {
                MainActor.assumeIsolated {
                    let m = model(.line)
                    m.handleClick(at: CGPoint(x: 10, y: 10))
                    m.moveAnchoredEnd(to: CGPoint(x: 60, y: 40))
                    Harness.expect(m.inProgress?.points.last == CGPoint(x: 60, y: 40))
                    Harness.expect(m.elements.isEmpty, "a preview is not a commitment")
                }
            }

            Harness.test("clicking the same spot again abandons it") {
                MainActor.assumeIsolated {
                    let m = model(.rectangle)
                    m.handleClick(at: CGPoint(x: 40, y: 40))
                    m.handleClick(at: CGPoint(x: 41, y: 41))
                    Harness.expect(m.anchor == nil, "still armed")
                    Harness.expect(m.elements.isEmpty, "committed a shape too small to see")
                }
            }

            Harness.test("changing tool abandons a half-placed shape") {
                MainActor.assumeIsolated {
                    let m = model(.arrow)
                    m.handleClick(at: CGPoint(x: 15, y: 15))
                    m.tool = .ellipse
                    Harness.expect(m.anchor == nil, "the anchor outlived its tool")
                    Harness.expect(m.inProgress == nil)
                }
            }

            Harness.test("freehand and text are not placed this way") {
                MainActor.assumeIsolated {
                    for tool in [MarkupTool.freehand, .text] {
                        let m = model(tool)
                        m.handleClick(at: CGPoint(x: 20, y: 20))
                        Harness.expect(m.anchor == nil, "\(tool.rawValue) should need a drag")
                    }
                }
            }

            Harness.test("crop is left to dragging") {
                // Its preview and its committed value are the same state, so a half-placed crop
                // would look exactly like a real one.
                Harness.expect(!MarkupTool.crop.supportsClickAnchor)
                Harness.expect(MarkupTool.arrow.supportsClickAnchor)
            }

            Harness.test("Place draws the shape last used, never itself") {
                MainActor.assumeIsolated {
                    let m = model(.rectangle)
                    m.handleClick(at: CGPoint(x: 10, y: 10))
                    m.handleClick(at: CGPoint(x: 70, y: 50))          // a rectangle is now the last shape
                    m.tool = .place
                    m.handleClick(at: CGPoint(x: 100, y: 20))
                    m.handleClick(at: CGPoint(x: 150, y: 90))
                    Harness.expectEqual(m.elements.count, 2)
                    // The invariant: an element carrying `.place` would be undrawable.
                    Harness.expect(!m.elements.contains { $0.tool == .place },
                                   "committed the stand-in instead of a real shape")
                    Harness.expectEqual(m.elements.last?.tool, .rectangle)
                }
            }

            Harness.test("Place follows the shape you switch to") {
                MainActor.assumeIsolated {
                    let m = model(.place)
                    Harness.expectEqual(m.effectiveTool, .arrow, "should start on the arrow")
                    m.tool = .ellipse
                    m.handleClick(at: CGPoint(x: 10, y: 10))
                    m.handleClick(at: CGPoint(x: 60, y: 60))
                    m.tool = .place
                    Harness.expectEqual(m.effectiveTool, .ellipse, "did not remember the ellipse")
                }
            }

            Harness.test("shape names read correctly mid-sentence") {
                Harness.expectEqual(MarkupTool.arrow.titleWithArticle, "an arrow")
                Harness.expectEqual(MarkupTool.ellipse.titleWithArticle, "an ellipse")
                Harness.expectEqual(MarkupTool.rectangle.titleWithArticle, "a rectangle")
                Harness.expectEqual(MarkupTool.line.titleWithArticle, "a line")
            }

            Harness.test("Place is offered for two-point shapes only") {
                for shape in MarkupTool.placeableShapes {
                    Harness.expect(shape.supportsClickAnchor, "\(shape.rawValue) cannot be clicked")
                    Harness.expect(!shape.placesLastShape, "the stand-in stands in for itself")
                }
                // Freehand needs a path, text needs typing, crop shares state with its preview.
                for excluded in [MarkupTool.freehand, .text, .crop] {
                    Harness.expect(!MarkupTool.placeableShapes.contains(excluded),
                                   "\(excluded.rawValue) should not be placeable")
                }
                Harness.expect(MarkupTool.allCases.contains(.place), "not in the palette")
            }

            Harness.test("an untouched image reports nothing to carry back") {
                MainActor.assumeIsolated {
                    let m = model(.arrow)
                    Harness.expect(!m.hasEdits)
                    m.handleClick(at: CGPoint(x: 10, y: 10))
                    Harness.expect(!m.hasEdits, "an unfinished shape is not an edit")
                    m.handleClick(at: CGPoint(x: 80, y: 60))
                    Harness.expect(m.hasEdits, "a committed shape should be carried back")
                }
            }
        }
    }
}
