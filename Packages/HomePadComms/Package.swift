// swift-tools-version: 6.2
import PackageDescription

// Messages as each household member's own Apple ID, through a Mac hub.
let package = Package(
    name: "HomePadComms",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadComms", targets: ["HomePadComms"]),
    ],
    dependencies: [
        .package(path: "../HomePadCore"),
        .package(path: "../HomePadUI"),
        .package(path: "CommsKit"),
    ],
    targets: [
        .target(
            name: "HomePadComms",
            dependencies: ["HomePadCore", "HomePadUI", "CommsKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomePadCommsTests",
            dependencies: ["HomePadComms", "CommsKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
