import Foundation
import AppKit
import CoreGraphics

/// Maps between AppKit screens and the 1-based display indices `screencapture -D` expects.
public enum DisplayLocator {

    /// The screen the pointer is currently on, falling back to the main screen.
    public static var screenUnderPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
    }

    public static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// `screencapture -D` numbers displays from 1, in active-display-list order, where 1 is main.
    public static var displayIndexUnderPointer: Int {
        guard let screen = screenUnderPointer, let target = displayID(for: screen) else { return 1 }
        return index(of: target)
    }

    static func index(of displayID: CGDirectDisplayID) -> Int {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return 1 }

        guard let position = displays.firstIndex(of: displayID) else { return 1 }
        return position + 1
    }
}
