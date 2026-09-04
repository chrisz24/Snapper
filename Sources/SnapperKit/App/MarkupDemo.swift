import AppKit
import Foundation

/// Opens the markup editor on a stand-in capture and holds it, so its appearance can be inspected.
///
///     dist/Snapper.app/Contents/MacOS/Snapper --markup-demo [seconds] [--tool place]
///
/// The editor is otherwise only reachable from a quick action on a real capture, which makes it the
/// one window in the app that could not be looked at without taking a screenshot first.
@MainActor
public enum MarkupDemo {

    public static func run(seconds: Double, tool: MarkupTool) async -> Int32 {
        // A throwaway preferences domain: the demo picks a tool, and doing that through the real
        // store would leave the choice behind in the user's settings.
        let suite = "snapper.markup-demo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults ?? .standard)
        settings.lastMarkupTool = tool.rawValue

        guard let image = OCRSelfTest.renderPage(width: 720, height: 460) else {
            print("could not render a stand-in capture")
            return 1
        }
        let url = AppInfo.scratchDirectory.appendingPathComponent("markup-demo.png")
        try? ImageWriter.pngData(image, scale: 2)?.write(to: url)

        let result = CaptureResult(fileURL: url, image: image, scale: 2,
                                   mode: .region, isTemporary: true)
        let controller = MarkupWindowController(settings: settings)
        controller.open(result)
        try? await Task.sleep(for: .milliseconds(900))

        // Seeded so a rendering change can be looked at without drawing by hand.
        if CommandLine.arguments.contains("--samples"), let model = controller.debugModel {
            let widths: [CGFloat] = [2, 4, 8, 14]
            for (index, width) in widths.enumerated() {
                let y = 520 + CGFloat(index) * 90
                model.commit(MarkupElement(
                    tool: .arrow,
                    points: [CGPoint(x: 120, y: y), CGPoint(x: 620, y: y)],
                    color: .red, lineWidth: width))
            }
            try? await Task.sleep(for: .milliseconds(400))
        }

        guard let window = controller.debugWindow else {
            print("no markup window")
            return 1
        }
        print("TOOL \(tool.rawValue)")
        print("WINDOWID \(window.windowNumber)")
        print("SIZE \(Int(window.frame.width))x\(Int(window.frame.height))")
        fflush(stdout)

        try? await Task.sleep(for: .seconds(seconds))
        return 0
    }
}
