// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SansAccent",
    platforms: [.macOS(.v14)],
    products: [
        // Used by Sans-Accent Pro, which builds on this open core.
        .library(name: "AccentCore", targets: ["AccentCore"]),
        .library(name: "SansAccentApp", targets: ["SansAccentApp"]),
        .executable(name: "SansAccent", targets: ["SansAccent"]),
    ],
    targets: [
        // Word logic: what to accent, what ⌥ cycles to. No AppKit, fully testable.
        .target(name: "AccentCore", path: "Sources/AccentCore"),
        // The menu bar app: keyboard tap, permissions, menu, and the extension point for Pro.
        .target(name: "SansAccentApp", dependencies: ["AccentCore"], path: "Sources/SansAccentApp"),
        // The free app: SansAccentApp with no extensions.
        .executableTarget(name: "SansAccent", dependencies: ["SansAccentApp"], path: "Sources/SansAccent"),
        // Types data/testset.tsv through the engine: swift run AccentBench
        .executableTarget(name: "AccentBench", dependencies: ["AccentCore"], path: "Sources/AccentBench"),
        .testTarget(name: "AccentCoreTests", dependencies: ["AccentCore"], path: "Tests/AccentCoreTests"),
    ]
)
