import Foundation

public struct FilenameContext: Sendable {
    public var date: Date
    /// Frontmost app at the moment of capture, if known.
    public var appName: String?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var modeName: String

    public init(
        date: Date = Date(),
        appName: String? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        modeName: String = "Screenshot"
    ) {
        self.date = date
        self.appName = appName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.modeName = modeName
    }
}

/// Expands filename templates like `Screenshot {date} at {time}`.
///
/// Pure and locale-pinned so the tests are deterministic regardless of the machine's region.
public enum FilenameTemplate {

    public static let defaultTemplate = "Screenshot {date} at {time}"

    public static let tokens: [(token: String, describes: String)] = [
        ("{date}", "2026-08-21"),
        ("{time}", "14.09.05 (24-hour, sorts correctly)"),
        ("{time12}", "2.09.05 PM"),
        ("{datetime}", "2026-08-21 14.09.05"),
        ("{app}", "name of the frontmost app"),
        ("{w}", "width in pixels"),
        ("{h}", "height in pixels"),
        ("{mode}", "Screenshot, Window, or Text"),
    ]

    public static func render(_ template: String, context: FilenameContext) -> String {
        let calendarLocale = Locale(identifier: "en_US_POSIX")

        func formatted(_ format: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = calendarLocale
            formatter.dateFormat = format
            return formatter.string(from: context.date)
        }

        // Colons are forbidden in filenames and slashes break paths; macOS itself uses dots here.
        let date = formatted("yyyy-MM-dd")
        let time = formatted("HH.mm.ss")
        let time12 = formatted("h.mm.ss a")

        var result = template
        let substitutions: [String: String] = [
            "{date}": date,
            "{time}": time,
            "{time12}": time12,
            "{datetime}": "\(date) \(time)",
            "{app}": context.appName ?? "",
            "{w}": String(context.pixelWidth),
            "{h}": String(context.pixelHeight),
            "{mode}": context.modeName,
        ]
        for (token, value) in substitutions {
            result = result.replacingOccurrences(of: token, with: value)
        }

        let cleaned = sanitize(result)
        return cleaned.isEmpty ? sanitize("\(context.modeName) \(date) at \(time)") : cleaned
    }

    /// Strips characters that are illegal or hostile in a filename, and collapses the runs of
    /// whitespace that an empty token like `{app}` leaves behind.
    public static func sanitize(_ name: String) -> String {
        var result = ""
        for scalar in name.unicodeScalars {
            switch scalar {
            case "/", ":", "\\":
                result.append("-")
            default:
                if CharacterSet.controlCharacters.contains(scalar) {
                    continue
                }
                result.unicodeScalars.append(scalar)
            }
        }
        // Leading dots would make the file invisible in Finder.
        while result.hasPrefix(".") { result.removeFirst() }
        let collapsed = result
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Appends " 2", " 3", … until the name is free, matching Finder's convention.
    public static func uniqueURL(
        directory: URL,
        basename: String,
        fileExtension: String,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let first = directory
            .appendingPathComponent(basename)
            .appendingPathExtension(fileExtension)
        if !exists(first) { return first }

        var counter = 2
        while true {
            let candidate = directory
                .appendingPathComponent("\(basename) \(counter)")
                .appendingPathExtension(fileExtension)
            if !exists(candidate) { return candidate }
            counter += 1
            if counter > 10_000 { return candidate } // pathological directory; give up gracefully
        }
    }
}
