import Foundation
import AppKit
import Carbon.HIToolbox

/// Opaque handle for one live registration.
public struct HotkeyToken: Hashable, Sendable {
    fileprivate let id: UInt32
}

/// Wraps Carbon's `RegisterEventHotKey`.
///
/// Carbon is used rather than an `NSEvent` global monitor for two reasons: it *consumes* the key
/// event (so ⌘C genuinely acts on the capture instead of also reaching the frontmost app), and it
/// needs no Accessibility permission.
///
/// Registrations come in two flavours, though the manager treats them identically — the
/// distinction lives in who holds the token:
///   * capture/OCR shortcuts, registered for the life of the app
///   * quick-action shortcuts, registered only while a `QuickActionSession` is alive
@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()

    private struct Registration {
        /// Nil while suspended — the record survives so it can be reinstated.
        var ref: EventHotKeyRef?
        let hotkey: Hotkey
        let handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    /// Depth rather than a flag, so overlapping suspensions cannot leave shortcuts stranded.
    private var suspensionDepth = 0

    /// Four-char code 'SNPR', identifying our hotkeys in the Carbon event stream.
    private static let signature: OSType = 0x534E5052

    private init() {}

    public var isSuspended: Bool { suspensionDepth > 0 }
    public var activeCount: Int { registrations.values.count { $0.ref != nil } }
    public var registeredCount: Int { registrations.count }

    /// Registers a combination. Returns nil if the OS refused it — almost always because another
    /// app (or the system) already owns that combination.
    @discardableResult
    public func register(_ hotkey: Hotkey, handler: @escaping () -> Void) -> HotkeyToken? {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        // While suspended, record the intent but leave it dormant, so a capture starting
        // mid-recording cannot resurrect a live shortcut behind the recorder's back.
        guard !isSuspended else {
            registrations[id] = Registration(ref: nil, hotkey: hotkey, handler: handler)
            return HotkeyToken(id: id)
        }

        guard let ref = carbonRegister(hotkey, id: id) else { return nil }
        registrations[id] = Registration(ref: ref, hotkey: hotkey, handler: handler)
        return HotkeyToken(id: id)
    }

    public func unregister(_ token: HotkeyToken) {
        guard let registration = registrations.removeValue(forKey: token.id) else { return }
        if let ref = registration.ref { UnregisterEventHotKey(ref) }
    }

    public func unregister(_ tokens: [HotkeyToken]) {
        tokens.forEach(unregister)
    }

    /// True if the combination is already registered by us.
    public func isRegistered(_ hotkey: Hotkey) -> Bool {
        registrations.values.contains { $0.hotkey == hotkey }
    }

    // MARK: - Suspension

    /// Hands every shortcut back to the system for the duration.
    ///
    /// This is what makes the shortcut recorder work at all. Carbon consumes a registered
    /// combination *before* it reaches any window, so pressing ⌥⌘4 while editing that very
    /// shortcut would fire a screen capture instead of being recorded. Suspending first leaves the
    /// recorder a clean slate.
    public func suspendAll() {
        suspensionDepth += 1
        guard suspensionDepth == 1 else { return }

        for (id, registration) in registrations {
            if let ref = registration.ref { UnregisterEventHotKey(ref) }
            registrations[id]?.ref = nil
        }
    }

    /// Reinstates everything suspended by `suspendAll()`.
    public func resumeAll() {
        guard suspensionDepth > 0 else { return }
        suspensionDepth -= 1
        guard suspensionDepth == 0 else { return }

        for (id, registration) in registrations where registration.ref == nil {
            registrations[id]?.ref = carbonRegister(registration.hotkey, id: id)
        }
    }

    /// Escape hatch for a suspension whose owner vanished (a settings window closed mid-recording,
    /// say). Without it the app would be left with no working shortcuts and no way back.
    public func forceResume() {
        guard suspensionDepth > 0 else { return }
        suspensionDepth = 1
        resumeAll()
    }

    // MARK: - Carbon plumbing

    private func carbonRegister(_ hotkey: Hotkey, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else { return nil }
        return ref
    }

    fileprivate func handle(id: UInt32) {
        guard !isSuspended else { return }
        registrations[id]?.handler()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), snapperHotkeyHandler, 1, &spec, nil, &handlerRef)
    }
}

/// C callback — cannot capture context, so it routes through the shared manager.
private let snapperHotkeyHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return OSStatus(eventNotHandledErr) }

    // Carbon delivers these on the main run loop.
    MainActor.assumeIsolated {
        HotkeyManager.shared.handle(id: hotKeyID.id)
    }
    return noErr
}
