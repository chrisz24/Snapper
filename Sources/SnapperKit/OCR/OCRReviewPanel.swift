import AppKit
import SwiftUI

/// Shows recognized text for review before it is used.
///
/// OCR is very good but not perfect, and a wrong character in a serial number or a URL is worse
/// than no text at all — so this is the opt-in path for anyone who would rather glance first.
@MainActor
public final class OCRReviewPanel: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    public override init() { super.init() }

    public func show(_ outcome: OCROutcome, onCopy: @escaping (String) -> Void) {
        close()

        let model = OCRReviewModel(text: outcome.text, confidence: outcome.averageConfidence)
        model.onCopy = { [weak self] text in
            onCopy(text)
            self?.close()
        }
        model.onCancel = { [weak self] in self?.close() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Recognized Text"
        window.contentView = NSHostingView(rootView: OCRReviewView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.delegate = self
        self.window = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window?.orderOut(nil)
        window = nil
    }
}

@MainActor
final class OCRReviewModel: ObservableObject {
    @Published var text: String
    let confidence: Float
    var onCopy: ((String) -> Void)?
    var onCancel: (() -> Void)?

    init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }

    var characterCount: Int { text.count }
    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count }
}

private struct OCRReviewView: View {
    @ObservedObject var model: OCRReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $model.text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5)
                )

            HStack {
                Text("\(model.wordCount) words · \(model.characterCount) characters · \(Int(model.confidence * 100))% confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.onCancel?() }
                    .keyboardShortcut(.cancelAction)
                Button("Copy") { model.onCopy?(model.text) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(minWidth: 380, minHeight: 260)
    }
}
