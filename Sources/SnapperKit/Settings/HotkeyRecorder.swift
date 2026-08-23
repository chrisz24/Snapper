import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click to edit, then press a combination. Esc cancels, Delete clears.
public struct HotkeyRecorder: NSViewRepresentable {
    @Binding public var hotkey: Hotkey?
    public var placeholder: String
    public var onChange: ((Hotkey?) -> Void)?

    public init(
        hotkey: Binding<Hotkey?>,
        placeholder: String = "Click to set",
        onChange: ((Hotkey?) -> Void)? = nil
    ) {
        self._hotkey = hotkey
        self.placeholder = placeholder
        self.onChange = onChange
    }

    public func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.placeholder = placeholder
        button.hotkey = hotkey
        button.onChange = { newValue in
            hotkey = newValue
            onChange?(newValue)
        }
        button.refreshTitle()
        return button
    }

    public func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.placeholder = placeholder
        guard !nsView.isRecording else { return }
        nsView.hotkey = hotkey
        nsView.refreshTitle()
    }
}

public final class RecorderButton: NSButton {
    var hotkey: Hotkey?
    var placeholder: String = "Click to set"
    var onChange: ((Hotkey?) -> Void)?

    private(set) var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            // Every registered shortcut has to stand down while recording. Carbon consumes a
            // combination before it reaches any window, so pressing the shortcut you are editing
            // would otherwise just run its action instead of being recorded.
            if isRecording {
                HotkeyManager.shared.suspendAll()
            } else {
                HotkeyManager.shared.resumeAll()
            }
            refreshTitle()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .systemFont(ofSize: 12, weight: .medium)
        target = self
        action = #selector(toggleRecording)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    public override var acceptsFirstResponder: Bool { true }

    /// Test hook: enter recording mode without a mouse click.
    public func beginRecordingForTesting() {
        isRecording = true
    }

    @objc private func toggleRecording() {
        // A recorder in an unfocused window receives no key events, so it would sit there saying
        // "Press keys…" and quietly ignore every one. Reclaim focus before arming it.
        if let window, !window.isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        window?.makeFirstResponder(self)
        isRecording.toggle()
    }

    func refreshTitle() {
        if isRecording {
            // Deliberately wiped: the previous combination is neither shown nor live, so the field
            // reads as an empty slot waiting for input rather than a shortcut that still works.
            attributedTitle = NSAttributedString(
                string: "Type a shortcut…",
                attributes: [
                    .foregroundColor: NSColor.controlAccentColor,
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                ]
            )
            toolTip = "Press a key combination. Esc cancels, Delete clears."
        } else if let hotkey {
            attributedTitle = NSAttributedString(
                string: hotkey.displayString,
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                ]
            )
            toolTip = "Click to record a different shortcut"
        } else {
            attributedTitle = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 12),
                ]
            )
            toolTip = "Click to record a shortcut"
        }
    }

    /// ⌘-based combinations are dispatched as key equivalents before `keyDown`, so recording ⌘C
    /// has to be intercepted here or the menu system would swallow it first.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return capture(event)
    }

    public override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        _ = capture(event)
    }

    private func capture(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            isRecording = false
            return true
        }

        if event.keyCode == UInt16(kVK_Delete), modifiers.isEmpty {
            hotkey = nil
            onChange?(nil)
            isRecording = false
            return true
        }

        // A bare key would fire constantly while typing anywhere else.
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return true
        }

        let candidate = Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        hotkey = candidate
        onChange?(candidate)
        isRecording = false
        return true
    }

    public override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    /// A settings window closed mid-recording would otherwise leave every shortcut suspended with
    /// nothing left alive to switch them back on.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { isRecording = false }
    }

    deinit {
        if isRecording {
            MainActor.assumeIsolated { HotkeyManager.shared.resumeAll() }
        }
    }
}

/// A recorder plus a clear button, which is how both settings tabs present a shortcut.
struct ShortcutField: View {
    @Binding var hotkey: Hotkey?
    var isEnabled: Bool = true
    var onChange: (Hotkey?) -> Void

    var body: some View {
        HStack(spacing: 4) {
            HotkeyRecorder(hotkey: $hotkey) { onChange($0) }
                .frame(width: 128, height: 22)
            Button {
                hotkey = nil
                onChange(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Reset to the default")
            .opacity(hotkey == nil ? 0 : 1)
            .disabled(hotkey == nil)
        }
        .disabled(!isEnabled)
    }
}
