import Foundation
import CoreGraphics

/// One recognized line, decoupled from Vision so the assembly rules can be tested directly.
///
/// `boundingBox` is normalized with a bottom-left origin, matching Vision's convention: larger
/// `y` means higher up the image.
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var boundingBox: CGRect
    /// Vision's own judgement that this line was only broken to fit the available width.
    /// Nil when unavailable, which sends the assembler to its geometry fallback.
    public var shouldWrapToNextLine: Bool?
    public var isTitle: Bool
    public var confidence: Float
    public var isRightToLeft: Bool

    public init(
        text: String,
        boundingBox: CGRect,
        shouldWrapToNextLine: Bool? = nil,
        isTitle: Bool = false,
        confidence: Float = 1,
        isRightToLeft: Bool = false
    ) {
        self.text = text
        self.boundingBox = boundingBox
        self.shouldWrapToNextLine = shouldWrapToNextLine
        self.isTitle = isTitle
        self.confidence = confidence
        self.isRightToLeft = isRightToLeft
    }
}

public struct TextAssemblyOptions: Equatable, Sendable {
    public var mode: LineBreakMode
    /// Rejoin words split across a line break with a trailing hyphen.
    public var dehyphenate: Bool
    /// Collapse runs of whitespace inside a line.
    public var collapseWhitespace: Bool

    public init(
        mode: LineBreakMode = .smartParagraphs,
        dehyphenate: Bool = true,
        collapseWhitespace: Bool = true
    ) {
        self.mode = mode
        self.dehyphenate = dehyphenate
        self.collapseWhitespace = collapseWhitespace
    }
}

/// Stitches recognized lines back into text.
///
/// This is where the "line breaks or not" setting actually lives. On macOS 26 the decision is made
/// from Vision's own `shouldWrapToNextLine` flag rather than guessing from line spacing; the
/// spacing heuristic only runs when that signal is absent.
public enum TextAssembler {

    /// Two fragments belong to the same visual line when their vertical spans overlap by more than
    /// this fraction of the shorter one.
    static let sameLineOverlapThreshold: CGFloat = 0.5

    /// Baseline-to-baseline distance beyond this multiple of the median line height reads as a
    /// paragraph break. Single-spaced body text sits around 1.2×.
    static let paragraphDistanceMultiple: CGFloat = 1.5

    public static func assemble(_ lines: [RecognizedLine], options: TextAssemblyOptions) -> String {
        let visualLines = groupIntoVisualLines(lines, collapseWhitespace: options.collapseWhitespace)
        guard !visualLines.isEmpty else { return "" }
        guard visualLines.count > 1 else {
            return visualLines[0].text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let medianHeight = median(visualLines.map(\.boundingBox.height))

        var result = ""
        for (index, line) in visualLines.enumerated() {
            var text = line.text

            let isLast = index == visualLines.count - 1
            let next = isLast ? nil : visualLines[index + 1]

            let separator: String
            if let next {
                separator = self.separator(
                    after: line,
                    before: next,
                    options: options,
                    medianHeight: medianHeight
                )
            } else {
                separator = ""
            }

            // Only drop the hyphen when the two halves are actually being rejoined.
            if options.dehyphenate, separator == " " || separator.isEmpty, !isLast,
               let next, endsWithHyphen(text), startsLowercase(next.text) {
                text = String(text.dropLast())
                result += text
                continue
            }

            result += text + separator
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Joining

    private static func separator(
        after line: VisualLine,
        before next: VisualLine,
        options: TextAssemblyOptions,
        medianHeight: CGFloat
    ) -> String {
        switch options.mode {
        case .preserveLines:
            return "\n"

        case .singleLine:
            return " "

        case .smartParagraphs:
            // A heading always owns its own line, whichever side of the break it is on.
            if line.isTitle || next.isTitle { return "\n" }

            if let wraps = line.shouldWrapToNextLine {
                return wraps ? " " : "\n"
            }

            // Fallback for when Vision offers no wrap signal: infer from line spacing.
            let distance = line.boundingBox.midY - next.boundingBox.midY
            if medianHeight > 0, distance > paragraphDistanceMultiple * medianHeight {
                return "\n\n"
            }
            return " "
        }
    }

    private static func endsWithHyphen(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return last == "-" || last == "\u{2010}" || last == "\u{2011}"
    }

    private static func startsLowercase(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return first.isLowercase
    }

    // MARK: - Visual line grouping

    struct VisualLine {
        var text: String
        var boundingBox: CGRect
        var shouldWrapToNextLine: Bool?
        var isTitle: Bool
    }

    /// Merges side-by-side fragments that sit on the same row into a single line.
    ///
    /// Vision returns observations per text region, so a single visual row can arrive as several
    /// pieces. Without this step they would each become their own line.
    static func groupIntoVisualLines(_ lines: [RecognizedLine], collapseWhitespace: Bool) -> [VisualLine] {
        let candidates = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !candidates.isEmpty else { return [] }

        // Top to bottom. Vision's origin is bottom-left, so descending midY is reading order.
        let sorted = candidates.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        var groups: [[RecognizedLine]] = []
        var groupBoxes: [CGRect] = []

        for line in sorted {
            if let lastIndex = groups.indices.last,
               verticallyOverlap(groupBoxes[lastIndex], line.boundingBox) {
                groups[lastIndex].append(line)
                groupBoxes[lastIndex] = groupBoxes[lastIndex].union(line.boundingBox)
            } else {
                groups.append([line])
                groupBoxes.append(line.boundingBox)
            }
        }

        return zip(groups, groupBoxes).map { fragments, box in
            let rightToLeft = fragments.contains(where: \.isRightToLeft)
            let ordered = fragments.sorted {
                rightToLeft
                    ? $0.boundingBox.minX > $1.boundingBox.minX
                    : $0.boundingBox.minX < $1.boundingBox.minX
            }
            var text = ordered.map(\.text).joined(separator: " ")
            if collapseWhitespace {
                text = text.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            return VisualLine(
                text: text,
                boundingBox: box,
                // The wrap decision belongs to the fragment that ends the row.
                shouldWrapToNextLine: ordered.last?.shouldWrapToNextLine,
                isTitle: fragments.contains(where: \.isTitle)
            )
        }
    }

    static func verticallyOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        let top = min(a.maxY, b.maxY)
        let bottom = max(a.minY, b.minY)
        let overlap = top - bottom
        guard overlap > 0 else { return false }
        let shorter = min(a.height, b.height)
        guard shorter > 0 else { return false }
        return overlap / shorter > sameLineOverlapThreshold
    }

    static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}
