import Foundation
import AppKit

/// Opens the settings window on a given tab and holds it, so its appearance can be screenshotted.
///
///     dist/Snapper.app/Contents/MacOS/Snapper --settings-demo general 6
@MainActor
public enum SettingsDemo {

    public static func run(settings: SettingsStore, bindings: HotkeyBindings,
                           tab: SettingsTab, seconds: Double) async -> Int32 {
        let controller = SettingsWindowController(settings: settings, bindings: bindings, onHotkeysChanged: {})
        controller.show(tab: tab)
        try? await Task.sleep(for: .milliseconds(900))

        guard let window = controller.debugWindow else {
            print("no settings window")
            return 1
        }

        // Capturing by window id rather than by screen rect: exact, and immune to which display
        // the window happened to be centred on.
        print("WINDOWID \(window.windowNumber)")
        print("SIZE \(Int(window.frame.width))x\(Int(window.frame.height))")
        fflush(stdout)

        try? await Task.sleep(for: .seconds(seconds))
        return 0
    }
}


/// Opens the first-run setup window and holds it, for inspection.
///
///     dist/Snapper.app/Contents/MacOS/Snapper --setup-demo 6
@MainActor
public enum SetupDemo {
    public static func run(settings: SettingsStore, bindings: HotkeyBindings,
                           seconds: Double, forceBlocked: Bool = false,
                           openGuide: Bool = false) async -> Int32 {
        let controller = SetupWindowController(settings: settings, bindings: bindings)
        controller.show(forcedBlocked: forceBlocked ? [
            (.captureFullScreen, "Screenshot (save screen to file)"),
            (.captureRegion, "Screenshot (save selection to file)"),
            (.captureWindow, "Screenshot and recording options"),
        ] : nil, openingGuide: openGuide)
        try? await Task.sleep(for: .milliseconds(900))

        guard let window = controller.debugWindow else {
            print("no setup window")
            return 1
        }
        print("WINDOWID \(window.windowNumber)")
        print("SIZE \(Int(window.frame.width))x\(Int(window.frame.height))")
        fflush(stdout)

        try? await Task.sleep(for: .seconds(seconds))
        return 0
    }
}
