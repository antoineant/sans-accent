// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SansAccent",
    platforms: [.macOS(.v14)],
    targets: [
        // Word logic: what to accent, what right ⌥ cycles to. No AppKit, fully testable.
        .target(name: "AccentCore", path: "Sources/AccentCore"),
        // The menu bar app: keyboard tap, permissions, menu.
        .executableTarget(name: "SansAccent", dependencies: ["AccentCore"], path: "Sources/SansAccent"),
        // Types data/testset.tsv through the engine: swift run AccentBench
        .executableTarget(name: "AccentBench", dependencies: ["AccentCore"], path: "Sources/AccentBench"),
        .testTarget(name: "AccentCoreTests", dependencies: ["AccentCore"], path: "Tests/AccentCoreTests"),
    ]
)
