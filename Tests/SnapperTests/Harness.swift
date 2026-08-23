import Foundation

/// A minimal test harness.
///
/// Command Line Tools ship neither XCTest nor swift-testing, so rather than take a network
/// dependency just to assert things, the suite is an ordinary executable. Everything under test is
/// public API, so no `@testable` import is needed.
enum Harness {
    nonisolated(unsafe) private static var currentSuite = ""
    nonisolated(unsafe) private static var failures: [String] = []
    nonisolated(unsafe) private static var passedCount = 0
    nonisolated(unsafe) private static var testCount = 0
    nonisolated(unsafe) private static var currentTestFailed = false

    static func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        print("\n\u{001B}[1m\(name)\u{001B}[0m")
        body()
    }

    static func test(_ name: String, _ body: () throws -> Void) {
        testCount += 1
        currentTestFailed = false
        do {
            try body()
        } catch {
            currentTestFailed = true
            failures.append("\(currentSuite) › \(name): threw \(error)")
        }
        if currentTestFailed {
            print("  \u{001B}[31m✗\u{001B}[0m \(name)")
        } else {
            passedCount += 1
            print("  \u{001B}[32m✓\u{001B}[0m \(name)")
        }
    }

    static func expect(
        _ condition: Bool,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard !condition else { return }
        currentTestFailed = true
        let detail = message().isEmpty ? "" : " — \(message())"
        let shortFile = URL(fileURLWithPath: "\(file)").lastPathComponent
        failures.append("\(currentSuite)\(detail) (\(shortFile):\(line))")
    }

    static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard actual != expected else { return }
        currentTestFailed = true
        let detail = message().isEmpty ? "" : " \(message())"
        let shortFile = URL(fileURLWithPath: "\(file)").lastPathComponent
        failures.append("\(currentSuite)\(detail): expected \(expected), got \(actual) (\(shortFile):\(line))")
    }

    static func finish() -> Never {
        print("\n" + String(repeating: "─", count: 60))
        if failures.isEmpty {
            print("\u{001B}[32m\(passedCount)/\(testCount) tests passed\u{001B}[0m")
            exit(0)
        } else {
            print("\u{001B}[31m\(failures.count) failure(s), \(passedCount)/\(testCount) passed\u{001B}[0m")
            for failure in failures { print("  • \(failure)") }
            exit(1)
        }
    }
}
