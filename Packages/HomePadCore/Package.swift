// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomePadCore",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "HomePadCore", targets: ["HomePadCore"]),
    ],
    targets: [
        .target(
            name: "HomePadCore",
            dependencies: ["HomePadObjC"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        /// Catches Objective-C exceptions from framework calls that raise them.
        .target(name: "HomePadObjC"),
        .testTarget(
            name: "HomePadCoreTests",
            dependencies: ["HomePadCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
