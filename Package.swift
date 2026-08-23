// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Snapper",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Snapper", targets: ["Snapper"]),
        .executable(name: "SnapperTests", targets: ["SnapperTests"]),
        .library(name: "SnapperKit", targets: ["SnapperKit"]),
    ],
    targets: [
        .executableTarget(
            name: "Snapper",
            dependencies: ["SnapperKit"],
            path: "Sources/Snapper",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "SnapperKit",
            path: "Sources/SnapperKit",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        // Command Line Tools ship neither XCTest nor swift-testing (both come with Xcode), so
        // the suite is a plain executable with a tiny built-in harness. `make test` runs it.
        .executableTarget(
            name: "SnapperTests",
            dependencies: ["SnapperKit"],
            path: "Tests/SnapperTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
