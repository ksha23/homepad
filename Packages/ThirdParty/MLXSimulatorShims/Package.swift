// swift-tools-version: 6.2
import PackageDescription

// Lets MLX link for the iOS Simulator, whose Metal SDK lacks two error domains
// MLX names at load time. MLX never runs in the simulator (the Natural voice
// falls back to the Apple voice there); this only satisfies the linker.
let package = Package(
    name: "MLXSimulatorShims",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MLXSimulatorShims", targets: ["MLXSimulatorShims"]),
    ],
    targets: [
        .target(name: "MLXSimulatorShims", linkerSettings: [.linkedFramework("Foundation")]),
    ]
)
