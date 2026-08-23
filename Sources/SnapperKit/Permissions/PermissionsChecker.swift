import Foundation
import AppKit
import CoreGraphics

/// Screen Recording is the one permission this app cannot work without — `screencapture` runs as
/// our child process, so the system attributes the check to us.
public enum PermissionsChecker {

    /// Non-prompting check.
    public static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system prompt if it has never been answered. Returns the immediate result,
    /// which is false the very first time even when the user goes on to approve — macOS requires a
    /// relaunch before the grant takes effect.
    @discardableResult
    public static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    public static func openKeyboardShortcutSettings() {
        // Where the system's own ⌘⇧3/4/5 screenshot shortcuts live, for users who want to free
        // one up and rebind it to Snapper.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!
        NSWorkspace.shared.open(url)
    }

    /// Relaunches the app, which is how a freshly granted Screen Recording permission takes hold.
    public static func relaunch() {
        guard let bundleURL = Bundle.main.bundleURL as URL? else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
