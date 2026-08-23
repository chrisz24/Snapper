import Foundation
import AppKit

/// Turns a capture into text, then routes it according to the user's settings.
@MainActor
public final class OCRService {
    private let settings: SettingsStore

    /// The user wants to see and edit the text before it is used.
    public var onReview: ((OCROutcome, CaptureResult) -> Void)?
    /// The capture should also get the usual preview treatment.
    public var onKeepImage: ((CaptureResult) -> Void)?

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public func options() -> OCROptions {
        OCROptions(
            recognitionLevel: settings.recognitionLevel,
            languages: settings.recognitionLanguages,
            automaticLanguageDetection: settings.automaticLanguageDetection,
            usesLanguageCorrection: settings.usesLanguageCorrection,
            customWords: settings.customWords,
            enhanceSmallSelections: settings.enhanceSmallSelections,
            assembly: TextAssemblyOptions(
                mode: settings.lineBreakMode,
                dehyphenate: settings.dehyphenate,
                collapseWhitespace: settings.collapseWhitespace
            )
        )
    }

    public func recognize(_ result: CaptureResult, keepImage: Bool) {
        Task { await performRecognition(result, keepImage: keepImage) }
    }

    func performRecognition(_ result: CaptureResult, keepImage: Bool) async {
        do {
            let outcome = try await TextRecognizer.recognize(result.image, options: options())

            guard !outcome.isEmpty else {
                HUD.shared.show("No text found in that selection", style: .info, duration: 2.2)
                return
            }

            if settings.showOCRReview {
                onReview?(outcome, result)
            } else if settings.autoCopyOCR {
                ClipboardWriter.write(text: outcome.text)
                HUD.shared.show(summary(for: outcome))
            }

            if keepImage && settings.keepOCRImage {
                onKeepImage?(result)
            }
        } catch {
            HUD.shared.show("Could not read text: \(error.localizedDescription)", style: .failure, duration: 3)
        }
    }

    func summary(for outcome: OCROutcome) -> String {
        let words = outcome.wordCount
        let unit = words == 1 ? "word" : "words"
        return "Copied \(words) \(unit)"
    }
}
