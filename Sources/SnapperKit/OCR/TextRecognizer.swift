import Foundation
import CoreGraphics
import CoreImage
import Vision

public struct OCROptions: Sendable {
    public var recognitionLevel: RecognitionLevelSetting
    public var languages: [String]
    public var automaticLanguageDetection: Bool
    public var usesLanguageCorrection: Bool
    public var customWords: [String]
    public var enhanceSmallSelections: Bool
    public var assembly: TextAssemblyOptions

    public init(
        recognitionLevel: RecognitionLevelSetting = .accurate,
        languages: [String] = ["en-US"],
        automaticLanguageDetection: Bool = true,
        usesLanguageCorrection: Bool = true,
        customWords: [String] = [],
        enhanceSmallSelections: Bool = true,
        assembly: TextAssemblyOptions = TextAssemblyOptions()
    ) {
        self.recognitionLevel = recognitionLevel
        self.languages = languages
        self.automaticLanguageDetection = automaticLanguageDetection
        self.usesLanguageCorrection = usesLanguageCorrection
        self.customWords = customWords
        self.enhanceSmallSelections = enhanceSmallSelections
        self.assembly = assembly
    }
}

public struct OCROutcome: Sendable {
    public var text: String
    public var lineCount: Int
    public var averageConfidence: Float
    /// True when the upscale path ran.
    public var wasEnhanced: Bool

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var characterCount: Int { text.count }

    public var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// Runs Vision text recognition and hands the results to `TextAssembler`.
public enum TextRecognizer {

    /// Selections smaller than this on their longest edge get upscaled first.
    static let smallSelectionThreshold: CGFloat = 600
    static let maximumUpscaleFactor: CGFloat = 3

    public static func recognize(_ image: CGImage, options: OCROptions) async throws -> OCROutcome {
        var working = image
        var enhanced = false

        if options.enhanceSmallSelections, let factor = upscaleFactor(for: image),
           let bigger = upscale(image, by: factor) {
            working = bigger
            enhanced = true
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = options.recognitionLevel == .fast ? .fast : .accurate
        request.usesLanguageCorrection = options.usesLanguageCorrection
        request.automaticallyDetectsLanguage = options.automaticLanguageDetection
        if !options.automaticLanguageDetection {
            request.recognitionLanguages = options.languages.map { Locale.Language(identifier: $0) }
        }
        if !options.customWords.isEmpty {
            request.customWords = options.customWords
        }

        let observations = try await request.perform(on: working)
        let lines = observations.map(recognizedLine(from:))
        let text = TextAssembler.assemble(lines, options: options.assembly)

        let confidences = lines.map(\.confidence)
        let average = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)

        return OCROutcome(
            text: text,
            lineCount: lines.count,
            averageConfidence: average,
            wasEnhanced: enhanced
        )
    }

    /// Languages this machine's Vision build can recognize, for the settings picker.
    public static var supportedLanguages: [String] {
        RecognizeTextRequest().supportedRecognitionLanguages.map(\.minimalIdentifier)
    }

    // MARK: - Mapping

    static func recognizedLine(from observation: RecognizedTextObservation) -> RecognizedLine {
        let candidate = observation.topCandidates(1).first
        let corners = [observation.topLeft, observation.topRight, observation.bottomLeft, observation.bottomRight]
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let box = CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )

        return RecognizedLine(
            text: candidate?.string ?? observation.transcript,
            boundingBox: box,
            shouldWrapToNextLine: observation.shouldWrapToNextLine,
            isTitle: observation.isTitle,
            confidence: candidate?.confidence ?? observation.confidence,
            isRightToLeft: observation.textDirection == .rightToLeft
        )
    }

    // MARK: - Enhancement

    /// Small on-screen text is the common case for a text grab, and Vision does measurably better
    /// with more pixels to work with.
    static func upscaleFactor(for image: CGImage) -> CGFloat? {
        let longestEdge = CGFloat(max(image.width, image.height))
        guard longestEdge > 0, longestEdge < smallSelectionThreshold else { return nil }
        let needed = (smallSelectionThreshold / longestEdge).rounded(.up)
        return min(maximumUpscaleFactor, max(2, needed))
    }

    static func upscale(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(factor, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
