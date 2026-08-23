import Foundation
import AppKit
import SnapperKit

enum CaptureArgumentTests {
    private static let out = URL(fileURLWithPath: "/tmp/shot.png")

    private static func args(_ mode: CaptureMode, _ options: CaptureOptions = CaptureOptions()) -> [String] {
        CaptureArgumentBuilder.arguments(for: CaptureRequest(mode: mode, options: options, outputURL: out))
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), args.index(after: i) < args.endIndex else { return nil }
        return args[args.index(after: i)]
    }

    static func run() {
        Harness.suite("CaptureArgumentBuilder") {
            Harness.test("region is interactive and leaves space-to-toggle-window available") {
                let a = args(.region)
                Harness.expect(a.contains("-i"))
                Harness.expectEqual(value(after: "-J", in: a), "selection")
                Harness.expect(!a.contains("-s"), "-s would lock out window mode, unlike ⌘⇧4")
            }

            Harness.test("window mode starts in the window picker") {
                Harness.expectEqual(value(after: "-J", in: args(.window)), "window")
            }

            Harness.test("full screen is non-interactive and targets a 1-based display") {
                let a = args(.fullScreen(displayIndex: 2))
                Harness.expect(!a.contains("-i"))
                Harness.expectEqual(value(after: "-D", in: a), "2")
            }

            Harness.test("a display index below 1 is clamped") {
                Harness.expectEqual(value(after: "-D", in: args(.fullScreen(displayIndex: 0))), "1")
            }

            Harness.test("never routes to the clipboard") {
                for mode in [CaptureMode.region, .window, .regionForOCR, .fullScreen(displayIndex: 1)] {
                    Harness.expect(!args(mode).contains("-c"), "-c would deprive us of the file")
                }
            }

            Harness.test("always captures PNG so preview, OCR and clipboard can decode it") {
                for format in ImageFormat.allCases {
                    Harness.expectEqual(value(after: "-t", in: args(.region, CaptureOptions(format: format))), "png",
                                        "format \(format.rawValue)")
                }
            }

            Harness.test("silent adds -x, shadow suppression adds -o") {
                Harness.expect(args(.region, CaptureOptions(silent: true)).contains("-x"))
                Harness.expect(!args(.region, CaptureOptions(silent: false)).contains("-x"))
                Harness.expect(args(.window, CaptureOptions(includeWindowShadow: false)).contains("-o"))
                Harness.expect(!args(.window, CaptureOptions(includeWindowShadow: true)).contains("-o"))
            }

            Harness.test("cursor and delay are dropped for interactive modes") {
                let interactive = args(.region, CaptureOptions(includeCursor: true, delaySeconds: 5))
                Harness.expect(!interactive.contains("-C"))
                Harness.expect(!interactive.contains("-T"))

                let direct = args(.fullScreen(displayIndex: 1), CaptureOptions(includeCursor: true, delaySeconds: 5))
                Harness.expect(direct.contains("-C"))
                Harness.expectEqual(value(after: "-T", in: direct), "5")
            }

            Harness.test("the output path is the final argument") {
                Harness.expectEqual(args(.region).last, "/tmp/shot.png")
            }
        }
    }
}
