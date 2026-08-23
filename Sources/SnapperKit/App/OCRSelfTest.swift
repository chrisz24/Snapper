import Foundation
import AppKit
import CoreGraphics

/// Exercises the real Vision pipeline against a rendered page.
///
/// Needs no Screen Recording permission, so it can verify the recognition and assembly path
/// independently of the capture path. Run with:
///
///     dist/Snapper.app/Contents/MacOS/Snapper --ocr-test
@MainActor
public enum OCRSelfTest {

    /// Deliberately shaped to exercise the interesting cases: a heading, a paragraph long enough to
    /// soft-wrap several times, a genuine paragraph break, and a hyphenated word split by a wrap.
    private static let heading = "Quarterly Report"
    private static let paragraphOne = """
    The committee reviewed the proposal at length and concluded that the existing arrangement \
    should continue without modification for the remainder of the period under considera\u{00AD}tion.
    """
    private static let paragraphTwo = """
    A second and entirely separate paragraph follows, so that a real break can be told apart \
    from a line that merely ran out of room.
    """

    public static func run() async -> Int32 {
        var failures = 0

        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            let mark = passed ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
            print("  \(mark) \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            if !passed { failures += 1 }
        }

        print("\n\u{001B}[1mOCR self-test\u{001B}[0m")

        guard let image = renderPage() else {
            print("  could not render the test page")
            return 1
        }
        check("rendered a test page", true, "\(image.width)×\(image.height) px")

        var results: [LineBreakMode: OCROutcome] = [:]
        for mode in LineBreakMode.allCases {
            var options = OCROptions()
            options.assembly = TextAssemblyOptions(mode: mode, dehyphenate: true, collapseWhitespace: true)
            do {
                results[mode] = try await TextRecognizer.recognize(image, options: options)
            } catch {
                check("recognition (\(mode.rawValue))", false, error.localizedDescription)
                return 1
            }
        }

        guard let smart = results[.smartParagraphs],
              let preserved = results[.preserveLines],
              let single = results[.singleLine]
        else { return 1 }

        check("recognized text", !smart.isEmpty,
              "\(smart.lineCount) lines, \(Int(smart.averageConfidence * 100))% mean confidence")
        check("found the heading", smart.text.contains("Quarterly"))

        let preservedBreaks = preserved.text.filter(\.isNewline).count
        let smartBreaks = smart.text.filter(\.isNewline).count
        check("preserve keeps more line breaks than smart", preservedBreaks > smartBreaks,
              "preserve=\(preservedBreaks), smart=\(smartBreaks)")

        check("smart keeps the paragraph boundary", smartBreaks >= 1, "\(smartBreaks) break(s)")
        check("single line has no breaks at all", !single.text.contains("\n"))

        // The body of paragraph one should come back as continuous prose, not one line per row.
        let rejoined = smart.text.contains("proposal at length and concluded")
        check("soft-wrapped lines were rejoined", rejoined)

        let dehyphenated = smart.text.contains("consideration") && !smart.text.contains("considera-")
        check("hyphen split across the wrap was healed", dehyphenated)

        print("\n\u{001B}[2m--- smart paragraphs ---\u{001B}[0m")
        print(smart.text)
        print("\n\u{001B}[2m--- preserve line breaks ---\u{001B}[0m")
        print(preserved.text)

        print("")
        if failures == 0 {
            print("\u{001B}[32mOCR self-test passed\u{001B}[0m\n")
        } else {
            print("\u{001B}[31m\(failures) check(s) failed\u{001B}[0m\n")
        }
        return failures == 0 ? 0 : 1
    }

    /// Draws the sample page. A narrow text column forces plenty of soft wraps.
    public static func renderPage(width: CGFloat = 560, height: CGFloat = 420) -> CGImage? {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let body = NSMutableParagraphStyle()
        body.lineSpacing = 2
        body.paragraphSpacing = 14

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: heading + "\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 26),
            .foregroundColor: NSColor.black,
            .paragraphStyle: body,
        ]))
        text.append(NSAttributedString(string: paragraphOne + "\n" + paragraphTwo, attributes: [
            .font: NSFont.systemFont(ofSize: 17),
            .foregroundColor: NSColor.black,
            .paragraphStyle: body,
        ]))

        text.draw(in: NSRect(x: 28, y: 24, width: width - 56, height: height - 48))

        // Focus must be released before asking for the backing image.
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
