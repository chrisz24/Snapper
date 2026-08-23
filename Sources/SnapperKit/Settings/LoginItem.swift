import Foundation
import ServiceManagement

/// Launch-at-login, via the modern SMAppService registration.
public enum LoginItem {

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the status actually achieved, which may differ from what was asked when the user
    /// has the item disabled in System Settings > General > Login Items.
    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
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
            return isEnabled
        } catch {
            NSLog("[Snapper] login item change failed: \(error.localizedDescription)")
            return isEnabled
        }
    }

    /// False when the app is somewhere macOS will not register a login item from.
    public static var isAvailable: Bool {
        SMAppService.mainApp.status != .notFound
    }

    public static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: "Enabled"
        case .notRegistered: "Not enabled"
        case .notFound: "Unavailable from this location — move Snapper to Applications first"
        case .requiresApproval: "Waiting for approval in System Settings"
        @unknown default: "Unknown"
        }
    }
}
