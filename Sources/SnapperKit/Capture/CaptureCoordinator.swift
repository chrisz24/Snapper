import Foundation
import AppKit

/// Orchestrates a capture from keystroke to finished artefact.
///
/// This is the one place the whole flow is legible: permission → grab → persist → clipboard →
/// history → preview → quick-action window.
@MainActor
public final class CaptureCoordinator {
    private let engine: CaptureEngine
    private let settings: SettingsStore

    /// Called with a finished image capture, for the preview and quick-action layers.
    public var onCaptured: ((CaptureResult) -> Void)?
    /// Called with a capture destined for text recognition.
    public var onTextCapture: ((CaptureResult) -> Void)?
    /// Called when something went wrong, with a user-facing message.
    public var onError: ((String) -> Void)?
    /// Called when Screen Recording permission is missing.
    public var onPermissionNeeded: (() -> Void)?

    /// Guards against a second capture starting while the picker is already on screen.
    private(set) public var isCapturing = false

    public init(engine: CaptureEngine = ScreencaptureCLIEngine(), settings: SettingsStore) {
        self.engine = engine
        self.settings = settings
    }

    public func capture(mode: CaptureMode) {
        Task { await performCapture(mode: mode) }
    }

    func performCapture(mode: CaptureMode) async {
        guard !isCapturing else { return }

        guard PermissionsChecker.hasScreenRecordingAccess else {
            onPermissionNeeded?()
            return
        }

        isCapturing = true
        defer { isCapturing = false }

        // Record the frontmost app before the picker appears, so the {app} filename token names
        // the app you were actually looking at.
        let frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName

        let resolvedMode = resolve(mode)
        let request = CaptureRequest(
            mode: resolvedMode,
            options: currentOptions(),
            outputURL: scratchURL()
        )

        do {
            guard let result = try await engine.capture(request) else {
                return // user pressed Esc
            }

            if resolvedMode.isForOCR {
                onTextCapture?(result)
                return
            }

            // Either way the file gets a readable name: a scratch capture keeps its UUID
            // otherwise, which is what a drag into Finder would be called.
            let finished = settings.autoSaveToDisk
                ? (try? persist(result, frontmostApp: frontmostApp)) ?? result
                : (try? rename(result, frontmostApp: frontmostApp)) ?? result

            if settings.autoCopyToClipboard {
                ClipboardWriter.write(finished)
            }

            onCaptured?(finished)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    /// Fills in the display index for full-screen grabs at the moment of capture.
    private func resolve(_ mode: CaptureMode) -> CaptureMode {
        if case .fullScreen = mode {
            return .fullScreen(displayIndex: DisplayLocator.displayIndexUnderPointer)
        }
        return mode
    }

    private func currentOptions() -> CaptureOptions {
        CaptureOptions(
            format: settings.imageFormat,
            includeCursor: settings.includeCursor,
            includeWindowShadow: settings.includeWindowShadow,
            delaySeconds: settings.captureDelay,
            silent: !settings.playCaptureSound
        )
    }

    private func scratchURL() -> URL {
        AppInfo.scratchDirectory
            .appendingPathComponent("capture-\(UUID().uuidString)")
            .appendingPathExtension(CaptureRequest.captureFormat.fileExtension)
    }

    /// Moves a scratch capture into the user's save folder, converting format if needed.
    @discardableResult
    public func persist(_ result: CaptureResult, frontmostApp: String?) throws -> CaptureResult {
        let context = FilenameContext(
            date: result.createdAt,
            appName: frontmostApp,
            pixelWidth: result.image.width,
            pixelHeight: result.image.height,
            modeName: Self.modeName(for: result.mode)
        )
        let basename = FilenameTemplate.render(settings.filenameTemplate, context: context)
        let format = settings.imageFormat
        let directory = settings.saveDirectory

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = FilenameTemplate.uniqueURL(
            directory: directory,
            basename: basename,
            fileExtension: format.fileExtension
        )

        if format == CaptureRequest.captureFormat {
            // Same format — a move keeps the original bytes and the DPI metadata intact.
            try FileManager.default.moveItem(at: result.fileURL, to: destination)
        } else {
            try ImageWriter.write(result.image, to: destination, format: format, scale: result.scale)
            try? FileManager.default.removeItem(at: result.fileURL)
        }

        var moved = result
        moved.fileURL = destination
        moved.isTemporary = false
        return moved
    }

    /// Gives a scratch capture the same templated name it would have had on disk, without moving
    /// it out of scratch.
    func rename(_ result: CaptureResult, frontmostApp: String?) throws -> CaptureResult {
        let basename = FilenameTemplate.render(
            settings.filenameTemplate,
            context: FilenameContext(
                date: result.createdAt,
                appName: frontmostApp,
                pixelWidth: result.image.width,
                pixelHeight: result.image.height,
                modeName: Self.modeName(for: result.mode)
            )
        )
        let destination = FilenameTemplate.uniqueURL(
            directory: AppInfo.scratchDirectory,
            basename: basename,
            fileExtension: result.fileURL.pathExtension
        )
        try FileManager.default.moveItem(at: result.fileURL, to: destination)

        var renamed = result
        renamed.fileURL = destination
        return renamed
    }

    static func modeName(for mode: CaptureMode) -> String {
        switch mode {
        case .region: "Screenshot"
        case .window: "Window"
        case .fullScreen: "Screen"
        case .regionForOCR: "Text"
        }
    }
}
