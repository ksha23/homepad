// swift-tools-version: 6.2
import PackageDescription

// Wire models and routes shared by the iPad module and the Mac hub.
// Its own package so the hub links only this, not HomePadComms.
let package = Package(
    name: "CommsKit",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "CommsKit", targets: ["CommsKit"]),
    ],
    targets: [
        .target(name: "CommsKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CommsKitTests", dependencies: ["CommsKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
