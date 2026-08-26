import Foundation
import ServiceManagement

/// Launch-at-login, via the modern SMAppService registration.
public enum LoginItem {

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// What actually happened, so the interface can explain a refusal instead of snapping the
    /// switch back with no reason given.
    public enum Outcome: Equatable {
        case enabled
        case disabled
        /// Registered, but switched off by hand in System Settings › General › Login Items.
        case needsApproval
        case failed(String)

        public var isEnabled: Bool { self == .enabled }
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Outcome {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("[Snapper] login item change failed: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }

        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        default: return enabled ? .failed(statusDescription) : .disabled
        }
    }

    /// Whether the bundle sits somewhere macOS will register a login item from.
    ///
    /// Decided by location rather than by `SMAppService.mainApp.status`, which reports `.notFound`
    /// for an app that has merely never been registered. Gating the control on that status left the
    /// switch permanently disabled — never registered, therefore never registerable — while telling
    /// the user to move an app that was already in the right place.
    public static var isAvailable: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let applicationFolders = FileManager.default.urls(
            for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])
        return applicationFolders.contains {
            path.hasPrefix($0.resolvingSymlinksInPath().path + "/")
        }
    }

    public static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Enabled"
        case .notRegistered: "Not enabled"
        case .requiresApproval:
            "Switched off in System Settings › General › Login Items — turn Snapper on there"
        case .notFound:
            // Never registered. Registering is still worth attempting from a valid location, so
            // this must not read as a dead end.
            isAvailable
                ? "Not enabled"
                : "Move Snapper to your Applications folder to launch it at login"
        @unknown default: "Unknown"
        }
    }

    /// Prints where the app is and what the system makes of it, for `--login-item-status`.
    public static var diagnosticReport: String {
        let raw: String
        switch SMAppService.mainApp.status {
        case .enabled: raw = "enabled"
        case .notRegistered: raw = "notRegistered"
        case .notFound: raw = "notFound"
        case .requiresApproval: raw = "requiresApproval"
        @unknown default: raw = "unknown"
        }
        return """
        bundle:    \(Bundle.main.bundleURL.path)
        in Applications: \(isAvailable ? "yes" : "no")
        SMAppService.mainApp.status: \(raw)
        toggle:    \(isAvailable ? "offered" : "disabled")
        reads as:  \(statusDescription)
        """
    }
}
