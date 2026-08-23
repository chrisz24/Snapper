import Foundation

/// Tracks which global shortcuts the system refused to hand over.
///
/// `RegisterEventHotKey` fails when another app already owns a combination. Without somewhere to
/// record that, the failure is invisible: the shortcut simply never fires and there is nothing in
/// the interface to explain why.
@MainActor
public final class HotkeyRegistry: ObservableObject {
    public static let shared = HotkeyRegistry()

    @Published public private(set) var unavailable: Set<GlobalAction> = []

    public init() {}

    public func record(unavailable: Set<GlobalAction>) {
        self.unavailable = unavailable
    }

    public func isUnavailable(_ action: GlobalAction) -> Bool {
        unavailable.contains(action)
    }
}
