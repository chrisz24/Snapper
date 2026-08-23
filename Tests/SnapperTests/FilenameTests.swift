import Foundation
import SnapperKit

enum FilenameTests {
    /// 2026-08-21 14:09:05 UTC, pinned so formatting is deterministic.
    private static var context: FilenameContext {
        var c = FilenameContext(date: Date(timeIntervalSince1970: 1_787_321_345))
        c.pixelWidth = 800
        c.pixelHeight = 600
        c.modeName = "Screenshot"
        return c
    }

    static func run() {
        Harness.suite("FilenameTemplate") {
            Harness.test("expands the default template") {
                let name = FilenameTemplate.render(FilenameTemplate.defaultTemplate, context: context)
                Harness.expect(name.hasPrefix("Screenshot 2026-08-21 at "), "got \(name)")
                Harness.expect(!name.contains(":"), "colons are illegal in filenames")
            }

            Harness.test("expands dimension and mode tokens") {
                Harness.expectEqual(FilenameTemplate.render("{mode} {w}x{h}", context: context), "Screenshot 800x600")
            }

            Harness.test("an empty {app} token does not leave a double space") {
                var c = context
                c.appName = nil
                Harness.expectEqual(FilenameTemplate.render("Shot {app} end", context: c), "Shot end")
            }

            Harness.test("replaces path-breaking characters") {
                var c = context
                c.appName = "Safari/Tech: Preview"
                Harness.expectEqual(FilenameTemplate.render("{app}", context: c), "Safari-Tech- Preview")
            }

            Harness.test("never produces a hidden file") {
                Harness.expect(!FilenameTemplate.sanitize("...hidden").hasPrefix("."))
            }

            Harness.test("falls back to a real name when the template renders empty") {
                let name = FilenameTemplate.render("{app}", context: context)
                Harness.expect(!name.isEmpty)
                Harness.expect(name.hasPrefix("Screenshot "), "got \(name)")
            }

            Harness.test("appends Finder-style counters on collision") {
                let taken: Set<String> = ["/tmp/Shot.png", "/tmp/Shot 2.png"]
                let url = FilenameTemplate.uniqueURL(
                    directory: URL(fileURLWithPath: "/tmp"), basename: "Shot", fileExtension: "png",
                    exists: { taken.contains($0.path) }
                )
                Harness.expectEqual(url.lastPathComponent, "Shot 3.png")
            }

            Harness.test("uses the plain name when nothing is in the way") {
                let url = FilenameTemplate.uniqueURL(
                    directory: URL(fileURLWithPath: "/tmp"), basename: "Shot", fileExtension: "png",
                    exists: { _ in false }
                )
                Harness.expectEqual(url.lastPathComponent, "Shot.png")
            }
        }
    }
}
