// swift-tools-version: 6.2
import PackageDescription

// The shared item model and App Group outbox. Its own package so the
// Send to HomePad Share extension links only this, not all of HomePadConnect.
let package = Package(
    name: "HomePadShareKit",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "HomePadShareKit", targets: ["HomePadShareKit"]),
    ],
    targets: [
        .target(
            name: "HomePadShareKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
