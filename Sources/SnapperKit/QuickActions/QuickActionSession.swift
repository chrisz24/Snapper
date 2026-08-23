import Foundation
import AppKit

/// Owns one capture's quick-action window: the deadline, and the hotkeys that are live during it.
///
/// The lifetime of this object *is* the "quick actions that last for a set amount of time"
/// behaviour. While it lives, ⌘C and friends are grabbed system-wide; when it dies they go back to
/// whatever app the user is in. Exactly one may be active at a time.
@MainActor
public final class QuickActionSession {
    public let result: CaptureResult
    private let bindings: HotkeyBindings
    private var tokens: [HotkeyToken] = []
    private var appSwitchObserver: NSObjectProtocol?

    public private(set) var isActive = true
    public private(set) var keysAreGrabbed = false

    public var onAction: ((QuickAction) -> Void)?
    /// Fired when the session ends for any reason other than an action being run.
    public var onExpire: (() -> Void)?

    // Defaulted to nil rather than `.shared`: a default argument is evaluated at the call site,
    // which is not guaranteed to be main-actor isolated.
    public init(result: CaptureResult, bindings: HotkeyBindings? = nil) {
        self.result = result
        self.bindings = bindings ?? .shared
    }

    // MARK: - Key grab

    /// Takes over the quick-action shortcuts system-wide.
    public func grabKeys() {
        guard isActive, !keysAreGrabbed else { return }
        keysAreGrabbed = true

        for action in QuickAction.allCases {
            guard bindings.isEnabled(action) else { continue }
            if action.requiresSavedFile && result.isTemporary { continue }

            let hotkey = bindings.hotkey(for: action)
            if let token = HotkeyManager.shared.register(hotkey, handler: { [weak self] in
                self?.fire(action)
            }) {
                tokens.append(token)
            }
        }
    }

    /// Hands the shortcuts back to whatever app the user is in.
    public func releaseKeys() {
        guard keysAreGrabbed else { return }
        keysAreGrabbed = false
        HotkeyManager.shared.unregister(tokens)
        tokens = []
    }

    /// Releases the keys the moment the user moves to another app, so a ⌘C meant for their editor
    /// is never swallowed by a preview they have already mentally moved on from.
    public func releaseOnAppSwitch() {
        guard appSwitchObserver == nil else { return }

        // Settle first: the capture itself churns the frontmost app.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.isActive else { return }

            self.appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                // Our own activation (for the Save panel) must not count as switching away.
                guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                MainActor.assumeIsolated {
                    self?.invalidate()
                }
            }
        }
    }

    private func fire(_ action: QuickAction) {
        guard isActive else { return }
        onAction?(action)
    }

    public func invalidate() {
        guard isActive else { return }
        isActive = false
        releaseKeys()
        if let appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver)
            self.appSwitchObserver = nil
        }
        onExpire?()
    }

    deinit {
        let captured = tokens
        let observer = appSwitchObserver
        Task { @MainActor in
            HotkeyManager.shared.unregister(captured)
            if let observer {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
        }
    }
}
