import Foundation
import CoreGraphics
import SnapperKit

enum TextAssemblerTests {

    /// Builds a line on a given row. Vision's origin is bottom-left, so row 0 sits highest.
    /// Default spacing (0.06) against height (0.05) gives a 1.2× baseline distance — normal single
    /// spacing, comfortably under the 1.5× paragraph threshold.
    private static func line(
        _ text: String,
        row: Int,
        spacing: CGFloat = 0.06,
        height: CGFloat = 0.05,
        wrap: Bool? = nil,
        isTitle: Bool = false,
        x: CGFloat = 0.1,
        width: CGFloat = 0.8,
        rightToLeft: Bool = false
    ) -> RecognizedLine {
        RecognizedLine(
            text: text,
            boundingBox: CGRect(x: x, y: 0.9 - CGFloat(row) * spacing, width: width, height: height),
            shouldWrapToNextLine: wrap,
            isTitle: isTitle,
            isRightToLeft: rightToLeft
        )
    }

    private static func assemble(_ lines: [RecognizedLine], _ mode: LineBreakMode,
                                 dehyphenate: Bool = true) -> String {
        TextAssembler.assemble(lines, options: TextAssemblyOptions(mode: mode, dehyphenate: dehyphenate))
    }

    static func run() {
        Harness.suite("TextAssembler — line break modes") {
            let wrapped = [
                line("The quick brown fox", row: 0, wrap: true),
                line("jumps over the lazy", row: 1, wrap: true),
                line("dog.", row: 2, wrap: false),
            ]

            Harness.test("preserve keeps every recognized line") {
                Harness.expectEqual(assemble(wrapped, .preserveLines),
                                    "The quick brown fox\njumps over the lazy\ndog.")
            }

            Harness.test("smart rejoins soft-wrapped lines using Vision's own wrap flag") {
                Harness.expectEqual(assemble(wrapped, .smartParagraphs),
                                    "The quick brown fox jumps over the lazy dog.")
            }

            Harness.test("single line collapses everything") {
                Harness.expectEqual(assemble(wrapped, .singleLine),
                                    "The quick brown fox jumps over the lazy dog.")
            }

            Harness.test("smart respects a hard break between paragraphs") {
                let text = assemble([
                    line("End of the first idea.", row: 0, wrap: false),
                    line("Start of the second.", row: 1, wrap: false),
                ], .smartParagraphs)
                Harness.expectEqual(text, "End of the first idea.\nStart of the second.")
            }
        }

        Harness.suite("TextAssembler — geometry fallback (no wrap signal)") {
            Harness.test("normal line spacing reads as a soft wrap") {
                let text = assemble([
                    line("continues onto", row: 0),
                    line("the next line", row: 1),
                ], .smartParagraphs)
                Harness.expectEqual(text, "continues onto the next line")
            }

            Harness.test("a wide gap reads as a paragraph break") {
                let text = assemble([
                    line("First paragraph.", row: 0, spacing: 0.14),
                    line("Second paragraph.", row: 1, spacing: 0.14),
                ], .smartParagraphs)
                Harness.expectEqual(text, "First paragraph.\n\nSecond paragraph.")
            }

            Harness.test("the wrap flag wins over spacing when both are present") {
                // Wide spacing would suggest a paragraph break, but Vision says it wraps.
                let text = assemble([
                    line("held together", row: 0, spacing: 0.14, wrap: true),
                    line("regardless", row: 1, spacing: 0.14),
                ], .smartParagraphs)
                Harness.expectEqual(text, "held together regardless")
            }
        }

        Harness.suite("TextAssembler — headings") {
            Harness.test("a title keeps its own line even amid wrapped text") {
                let text = assemble([
                    line("Chapter One", row: 0, wrap: true, isTitle: true),
                    line("The body text begins", row: 1, wrap: true),
                    line("and continues here.", row: 2, wrap: false),
                ], .smartParagraphs)
                Harness.expectEqual(text, "Chapter One\nThe body text begins and continues here.")
            }
        }

        Harness.suite("TextAssembler — hyphenation") {
            Harness.test("rejoins a word split across a wrap") {
                let text = assemble([
                    line("This docu-", row: 0, wrap: true),
                    line("ment continues.", row: 1, wrap: false),
                ], .smartParagraphs)
                Harness.expectEqual(text, "This document continues.")
            }

            Harness.test("leaves a real hyphen before a capitalised word alone") {
                let text = assemble([
                    line("the Anglo-", row: 0, wrap: true),
                    line("Saxon period", row: 1, wrap: false),
                ], .smartParagraphs)
                Harness.expectEqual(text, "the Anglo- Saxon period")
            }

            Harness.test("never rejoins when preserving line breaks") {
                let text = assemble([
                    line("This docu-", row: 0, wrap: true),
                    line("ment continues.", row: 1),
                ], .preserveLines)
                Harness.expectEqual(text, "This docu-\nment continues.")
            }

            Harness.test("can be switched off") {
                let text = assemble([
                    line("This docu-", row: 0, wrap: true),
                    line("ment continues.", row: 1, wrap: false),
                ], .smartParagraphs, dehyphenate: false)
                Harness.expectEqual(text, "This docu- ment continues.")
            }

            Harness.test("handles the Unicode hyphen, not just ASCII") {
                let text = assemble([
                    line("This docu\u{2010}", row: 0, wrap: true),
                    line("ment continues.", row: 1, wrap: false),
                ], .smartParagraphs)
                Harness.expectEqual(text, "This document continues.")
            }
        }

        Harness.suite("TextAssembler — layout") {
            Harness.test("merges side-by-side fragments into one row, left to right") {
                // Deliberately supplied out of order.
                let text = assemble([
                    line("World", row: 0, x: 0.5, width: 0.2),
                    line("Hello", row: 0, x: 0.1, width: 0.2),
                ], .preserveLines)
                Harness.expectEqual(text, "Hello World")
            }

            Harness.test("orders right-to-left rows from the right") {
                let text = assemble([
                    line("first", row: 0, x: 0.5, width: 0.2, rightToLeft: true),
                    line("second", row: 0, x: 0.1, width: 0.2, rightToLeft: true),
                ], .preserveLines)
                Harness.expectEqual(text, "first second")
            }

            Harness.test("sorts rows top to bottom regardless of input order") {
                let text = assemble([
                    line("third", row: 2),
                    line("first", row: 0),
                    line("second", row: 1),
                ], .preserveLines)
                Harness.expectEqual(text, "first\nsecond\nthird")
            }
        }

        Harness.suite("TextAssembler — edge cases") {
            Harness.test("empty input yields empty output") {
                Harness.expectEqual(assemble([], .smartParagraphs), "")
            }

            Harness.test("blank observations are discarded") {
                let text = assemble([
                    line("real text", row: 0),
                    line("   ", row: 1),
                ], .preserveLines)
                Harness.expectEqual(text, "real text")
            }

            Harness.test("a single line comes back trimmed") {
                Harness.expectEqual(assemble([line("  solo  ", row: 0)], .smartParagraphs), "solo")
            }

            Harness.test("collapses runs of whitespace inside a line") {
                let lines = [line("spaced     out", row: 0)]
                let collapsed = TextAssembler.assemble(
                    lines, options: TextAssemblyOptions(mode: .preserveLines, collapseWhitespace: true))
                Harness.expectEqual(collapsed, "spaced out")
            }

            Harness.test("leaves inner whitespace alone when asked to") {
                let lines = [line("spaced     out", row: 0)]
                let kept = TextAssembler.assemble(
                    lines, options: TextAssemblyOptions(mode: .preserveLines, collapseWhitespace: false))
                Harness.expectEqual(kept, "spaced     out")
            }
        }
    }
}
