// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NtfyNative",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ntfy-native", targets: ["NtfyNative"]),
        .executable(name: "ntfy-live-smoke", targets: ["NtfyLiveSmoke"]),
        .library(name: "NtfyCore", targets: ["NtfyCore"])
    ],
    targets: [
        .target(name: "NtfyCore", resources: [.process("Resources")]),
        .executableTarget(name: "NtfyNative", dependencies: ["NtfyCore"], resources: [.process("Resources")]),
        .executableTarget(name: "NtfyLiveSmoke", dependencies: ["NtfyCore"]),
        .testTarget(name: "NtfyCoreTests", dependencies: ["NtfyCore"])
    ]
)
