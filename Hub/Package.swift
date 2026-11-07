// swift-tools-version: 6.2
import PackageDescription

// homepad-hub: the Mac side of HomePad's Messages.
// One process per Apple ID, run as that macOS user. See docs/COMMS.md.
let package = Package(
    name: "HomePadHub",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "homepad-hub", targets: ["homepad-hub"]),
    ],
    dependencies: [
        .package(path: "../Packages/HomePadComms/CommsKit"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", exact: "2.27.1"),
    ],
    targets: [
        .target(
            name: "HubCore",
            dependencies: ["CommsKit", .product(name: "Hummingbird", package: "hummingbird")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "homepad-hub",
            dependencies: ["HubCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "HubCoreTests", dependencies: ["HubCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
