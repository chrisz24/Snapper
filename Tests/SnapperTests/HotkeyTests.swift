import Foundation
import AppKit
import SnapperKit

enum HotkeyTests {
    static func run() {
        Harness.suite("Hotkey") {
            Harness.test("round-trips through Codable") {
                let original = Hotkey(keyCode: 31, modifiers: [.command, .shift])
                let data = try JSONEncoder().encode(original)
                let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
                Harness.expectEqual(decoded, original)
            }

            Harness.test("renders modifiers in conventional macOS order") {
                Harness.expectEqual(Hotkey(keyCode: 31, modifiers: [.command, .shift]).displayString, "⇧⌘O")
                Harness.expectEqual(Hotkey(keyCode: 8, modifiers: [.command]).displayString, "⌘C")
                Harness.expectEqual(
                    Hotkey(keyCode: 21, modifiers: [.command, .option, .control, .shift]).displayString,
                    "⌃⌥⇧⌘4"
                )
            }

            Harness.test("maps to Carbon modifier bits") {
                let hotkey = Hotkey(keyCode: 8, modifiers: [.command, .shift])
                Harness.expect(hotkey.carbonModifiers & 0x0100 != 0, "cmdKey")
                Harness.expect(hotkey.carbonModifiers & 0x0200 != 0, "shiftKey")
                Harness.expect(hotkey.carbonModifiers & 0x0800 == 0, "optionKey should be absent")
            }

            Harness.test("ignores device-dependent flag noise") {
                let withNoise = Hotkey(keyCode: 8, modifiers: [.command, .function, .numericPad])
                let plain = Hotkey(keyCode: 8, modifiers: [.command])
                Harness.expectEqual(withNoise.carbonModifiers, plain.carbonModifiers)
            }

            Harness.test("flags unmodified and system-reserved combinations") {
                Harness.expect(Hotkey(keyCode: 8, modifiers: []).isLikelyReserved, "bare keys")
                Harness.expect(Hotkey(keyCode: 49, modifiers: [.command]).isLikelyReserved, "⌘Space")
                Harness.expect(!Hotkey(keyCode: 31, modifiers: [.command, .shift]).isLikelyReserved, "⇧⌘O is free")
            }
        }
    }
}
