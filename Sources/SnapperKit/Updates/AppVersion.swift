import Foundation

/// A release version, comparable the way people expect: `0.10.0` is newer than `0.9.9`.
///
/// Plain string comparison gets that backwards, and `compare(options: .numeric)` gets it right
/// only until a pre-release suffix turns up. So a tag is parsed once, here, and every comparison
/// in the updater goes through this type.
///
/// Accepts what GitHub tags actually look like: `1.2.3`, `v1.2.3`, `1.2`, `1.2.3-beta.2`,
/// `v2.0.0-rc.1+build57`. Build metadata after `+` is kept for display but ignored when
/// comparing, as semver requires.
public struct AppVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    /// Numeric components exactly as written — `1.2` stays two long. Comparison pads with zeros.
    public let components: [Int]
    /// Whatever followed the first `-`: `beta.2` in `1.2.0-beta.2`. Empty for a final release.
    public let prerelease: String
    /// Whatever followed `+`. Display only.
    public let build: String

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, first == "v" || first == "V" { text.removeFirst() }
        guard !text.isEmpty else { return nil }

        var build = ""
        if let plus = text.firstIndex(of: "+") {
            build = String(text[text.index(after: plus)...])
            text = String(text[..<plus])
        }

        var prerelease = ""
        if let dash = text.firstIndex(of: "-") {
            prerelease = String(text[text.index(after: dash)...])
            text = String(text[..<dash])
        }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var components: [Int] = []
        for part in parts {
            // `Int("+1")` and `Int(" 1")` both fail already; this also rejects "1.2.x".
            guard let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }

        self.components = components
        self.prerelease = prerelease
        self.build = build
    }

    /// True for anything carrying a pre-release suffix, whatever the release was flagged as on
    /// GitHub. A tag saying `-beta` is a beta even if whoever published it forgot the checkbox.
    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        var text = components.map(String.init).joined(separator: ".")
        if !prerelease.isEmpty { text += "-\(prerelease)" }
        if !build.isEmpty { text += "+\(build)" }
        return text
    }

    /// The version without its build metadata — what belongs in a sentence shown to someone.
    public var displayString: String {
        var text = components.map(String.init).joined(separator: ".")
        if !prerelease.isEmpty { text += "-\(prerelease)" }
        return text
    }

    // MARK: - Comparable

    /// Build metadata is excluded deliberately: semver says it carries no precedence, and two
    /// builds of the same version are the same release as far as "is there an update" goes.
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compareNumbers(lhs, rhs) == 0 && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        // Must agree with `==`, which pads: 1.2 and 1.2.0 are equal and so must hash alike.
        hasher.combine(Self.padded(components, to: 4))
        hasher.combine(prerelease)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let numbers = compareNumbers(lhs, rhs)
        if numbers != 0 { return numbers < 0 }
        return comparePrerelease(lhs.prerelease, rhs.prerelease) < 0
    }

    private static func padded(_ components: [Int], to width: Int) -> [Int] {
        components + Array(repeating: 0, count: max(0, width - components.count))
    }

    private static func compareNumbers(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        let width = max(lhs.components.count, rhs.components.count)
        let a = padded(lhs.components, to: width)
        let b = padded(rhs.components, to: width)
        for (x, y) in zip(a, b) where x != y { return x < y ? -1 : 1 }
        return 0
    }

    /// Semver precedence for pre-release identifiers: a release outranks any pre-release of the
    /// same numbers, numeric identifiers compare numerically and rank below alphanumeric ones,
    /// and a shorter run of identifiers ranks below a longer one that matches so far.
    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> Int {
        if lhs == rhs { return 0 }
        if lhs.isEmpty { return 1 }
        if rhs.isEmpty { return -1 }

        let a = lhs.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let b = rhs.split(separator: ".", omittingEmptySubsequences: false).map(String.init)

        for index in 0..<max(a.count, b.count) {
            guard index < a.count else { return -1 }
            guard index < b.count else { return 1 }
            let x = a[index], y = b[index]
            switch (Int(x), Int(y)) {
            case let (xn?, yn?):
                if xn != yn { return xn < yn ? -1 : 1 }
            case (nil, .some):
                return 1
            case (.some, nil):
                return -1
            case (nil, nil):
                if x != y { return x < y ? -1 : 1 }
            }
        }
        return 0
    }
}
