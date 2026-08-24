import Foundation
import AppKit

/// Non-interactive smoke test of the capture pipeline.
///
/// The interactive modes need a human to drag a rectangle, but the full-screen path exercises
/// everything else — permission, process launch, PNG decode, DPI/scale recovery, format
/// conversion, filename templating, and collision handling. Run it with:
///
///     dist/Snapper.app/Contents/MacOS/Snapper --self-test
///
/// Running the binary from inside the bundle matters: it is what makes macOS attribute the Screen
/// Recording check to the app rather than to the terminal.
@MainActor
public enum SelfTest {

    public static func run(settings: SettingsStore) async -> Int32 {
        var failures = 0

        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            let mark = passed ? "\u{001B}[32m✓\u{001B}[0m" : "\u{001B}[31m✗\u{001B}[0m"
            print("  \(mark) \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            if !passed { failures += 1 }
        }

        print("\n\u{001B}[1mSnapper self-test\u{001B}[0m")
        print("  bundle: \(Bundle.main.bundleIdentifier ?? "nil")  version: \(AppInfo.version)")

        // 1. Permission
        let granted = PermissionsChecker.hasScreenRecordingAccess
        check("Screen Recording permission", granted,
              granted ? "" : "grant it in System Settings, then re-run")
        guard granted else {
            PermissionsChecker.openScreenRecordingSettings()
            return 1
        }

        // 2. Capture, into a scratch folder so the Desktop stays clean.
        let sandbox = AppInfo.supportDirectory.appendingPathComponent("SelfTest", isDirectory: true)
        try? FileManager.default.removeItem(at: sandbox)
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        // These are the user's real, persisted settings — SettingsStore.shared is UserDefaults-backed
        // — so they have to go back exactly as they were. Without this, running a diagnostic leaves
        // the app permanently saving captures into the self-test sandbox with the shutter muted, and
        // nothing says so.
        let previousSaveDirectory = settings.saveDirectoryPath
        let previousAutoSave = settings.autoSaveToDisk
        let previousShutter = settings.playCaptureSound
        defer {
            settings.saveDirectoryPath = previousSaveDirectory
            settings.autoSaveToDisk = previousAutoSave
            settings.playCaptureSound = previousShutter
        }

        settings.saveDirectoryPath = sandbox.path
        settings.autoSaveToDisk = true
        settings.playCaptureSound = false

        let coordinator = CaptureCoordinator(settings: settings)
        var captured: CaptureResult?
        var errorMessage: String?
        coordinator.onCaptured = { captured = $0 }
        coordinator.onError = { errorMessage = $0 }

        let index = DisplayLocator.displayIndexUnderPointer
        check("display index resolved", index >= 1, "display \(index)")

        await coordinator.performCapture(mode: .fullScreen(displayIndex: index))

        guard let result = captured else {
            check("capture produced a result", false, errorMessage ?? "no result and no error")
            return 1
        }

        check("capture produced a result", true)
        check("file exists on disk", FileManager.default.fileExists(atPath: result.fileURL.path),
              result.fileURL.lastPathComponent)
        check("image has real dimensions", result.image.width > 0 && result.image.height > 0,
              "\(result.image.width)×\(result.image.height) px")
        check("Retina scale recovered from DPI", result.scale >= 1,
              "\(result.scale)× → \(Int(result.pointSize.width))×\(Int(result.pointSize.height)) pt")
        check("moved out of scratch", !result.isTemporary)
        // The default template starts with the literal word "Screenshot"; {mode} is not involved.
        let expectedPrefix = FilenameTemplate.render(
            settings.filenameTemplate,
            context: FilenameContext(date: result.createdAt,
                                     modeName: CaptureCoordinator.modeName(for: result.mode))
        )
        check("filename follows the template",
              result.fileURL.deletingPathExtension().lastPathComponent == expectedPrefix,
              result.fileURL.lastPathComponent)

        // 3. Clipboard round-trip
        // Diagnose the encoder before trusting the pasteboard result.
        let img = result.image
        let cs = img.colorSpace
        print("    image: \(img.bitsPerComponent)bpc \(img.bitsPerPixel)bpp "
              + "alpha=\(img.alphaInfo.rawValue) "
              + "float=\(img.bitmapInfo.contains(.floatComponents)) "
              + "space=\(cs?.name.map(String.init(describing:)) ?? "nil") "
              + "model=\(cs?.model.rawValue ?? -1)")
        let png = ImageWriter.pngData(img, scale: result.scale)
        check("PNG encode succeeds", png != nil, png.map { "\($0.count / 1024) KB" } ?? "returned nil")

        ClipboardWriter.write(result)
        let board = NSPasteboard.general
        let pasteboardHasImage = board.canReadObject(forClasses: [NSImage.self], options: nil)
        check("clipboard accepts the capture", pasteboardHasImage)
        check("clipboard round-trips to an NSImage", NSImage(pasteboard: board) != nil)
        // One item, several types — two items would paste the picture twice.
        let itemCount = board.pasteboardItems?.count ?? 0
        check("clipboard holds exactly one item", itemCount == 1, "\(itemCount) item(s)")
        check("a pasting app sees a single image",
              (board.readObjects(forClasses: [NSImage.self], options: nil) ?? []).count == 1)

        // 4. Format conversion, the path a non-PNG delivery format takes.
        let jpegURL = sandbox.appendingPathComponent("converted.jpg")
        do {
            try ImageWriter.write(result.image, to: jpegURL, format: .jpg, scale: result.scale)
            let attributes = try FileManager.default.attributesOfItem(atPath: jpegURL.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            check("converts to JPEG", size > 0, "\(size / 1024) KB")
        } catch {
            check("converts to JPEG", false, error.localizedDescription)
        }

        // 5. Collision handling against files that genuinely exist.
        let firstName = result.fileURL.deletingPathExtension().lastPathComponent
        let second = FilenameTemplate.uniqueURL(directory: sandbox, basename: firstName, fileExtension: "png")
        check("collides onto a numbered name", second.lastPathComponent == "\(firstName) 2.png",
              second.lastPathComponent)

        print("")
        if failures == 0 {
            print("\u{001B}[32mself-test passed\u{001B}[0m — artefacts in \(sandbox.path)\n")
        } else {
            print("\u{001B}[31m\(failures) check(s) failed\u{001B}[0m\n")
        }
        return failures == 0 ? 0 : 1
    }
}
