import Foundation

/// What kind of device a tracker is, for its symbol and for matching what
/// people say ("my phone", "the iPad").
enum FindMyDeviceKind: String, CaseIterable, Sendable {
    case iPhone, iPad, watch, laptop, mac, airPods, vision, phone, other

    /// Guesses from the model ("iPhone 17 Pro", "iPad16,3") and then the name.
    init(model: String?, name: String) {
        self = Self.kind(in: model ?? "") ?? Self.kind(in: name) ?? .other
    }

    private static func kind(in text: String) -> FindMyDeviceKind? {
        let lower = text.lowercased()
        let rules: [(String, FindMyDeviceKind)] = [
            ("iphone", .iPhone), ("ipad", .iPad), ("watch", .watch), ("macbook", .laptop),
            ("airpods", .airPods), ("vision", .vision), ("imac", .mac), ("mac mini", .mac),
            ("mac studio", .mac), ("mac pro", .mac), ("mac", .mac), ("pixel", .phone),
            ("galaxy", .phone), ("android", .phone), ("phone", .phone),
        ]
        return rules.first { lower.contains($0.0) }?.1
    }

    var systemImage: String {
        switch self {
        case .iPhone, .phone: "iphone"
        case .iPad: "ipad"
        case .watch: "applewatch"
        case .laptop: "laptopcomputer"
        case .mac: "desktopcomputer"
        case .airPods: "airpods"
        case .vision: "vision.pro"
        case .other: "location.fill"
        }
    }

    /// Words people use for this kind, for the assistant's matching.
    var spokenWords: Set<String> {
        switch self {
        case .iPhone, .phone: ["phone", "phones", "iphone", "iphones", "cell", "mobile"]
        case .iPad: ["ipad", "ipads", "tablet", "tablets"]
        case .watch: ["watch", "watches", "applewatch"]
        case .laptop: ["mac", "macs", "macbook", "macbooks", "laptop", "laptops", "computer", "computers"]
        case .mac: ["mac", "macs", "imac", "computer", "computers", "desktop"]
        case .airPods: ["airpods", "headphones", "earbuds"]
        case .vision: ["vision", "headset"]
        case .other: []
        }
    }
}
