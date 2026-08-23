import Foundation

/// Builds the argument vector for `/usr/sbin/screencapture`.
///
/// Deliberately pure and separate from the process launching, so every flag combination can be
/// unit-tested without putting a capture overlay on screen.
public enum CaptureArgumentBuilder {

    public static func arguments(for request: CaptureRequest) -> [String] {
        var args: [String] = []

        switch request.mode {
        case .region, .regionForOCR:
            // -J selection starts in drag mode but leaves space-to-toggle-window available,
            // matching ⌘⇧4. (-s would lock out window mode entirely.)
            args += ["-i", "-J", "selection"]
        case .window:
            args += ["-i", "-J", "window"]
        case .fullScreen(let displayIndex):
            args += ["-D", String(max(1, displayIndex))]
        }

        if request.options.silent {
            args.append("-x")
        }

        // Window shadows are only meaningful when a window was picked.
        if !request.options.includeWindowShadow {
            args.append("-o")
        }

        // The cursor can only be composited in non-interactive modes.
        if request.options.includeCursor && !request.mode.isInteractive {
            args.append("-C")
        }

        // A delay before an interactive overlay makes no sense; only honour it for direct grabs.
        if request.options.delaySeconds > 0 && !request.mode.isInteractive {
            args += ["-T", String(request.options.delaySeconds)]
        }

        args += ["-t", CaptureRequest.captureFormat.fileExtension]

        // Never -c: the clipboard route would deprive us of the file we need for the preview,
        // OCR, history, and save-as.
        args.append(request.outputURL.path)
        return args
    }
}
