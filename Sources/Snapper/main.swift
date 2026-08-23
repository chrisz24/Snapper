import AppKit
import SnapperKit

// AppKit lifecycle rather than SwiftUI's App/MenuBarExtra: this app lives or dies on precise
// control of floating, non-activating panels, which MenuBarExtra actively fights.
//
// Top-level code runs on the main thread, but isn't statically main-actor isolated in Swift 5
// language mode, hence the explicit assumption.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    // NSApplication.delegate is weak, so this local must outlive run() — it does, since run()
    // blocks until termination.
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory) // menu bar only, no Dock icon
    application.run()
}
