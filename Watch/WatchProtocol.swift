import Foundation

/// Keys shared with the iPhone's `WatchBridge` (HomePadConnect/Watch/WatchBridge.swift).
/// Keep the two in sync.
enum WatchMessage {
    static let request = "request"
    static let snapshot = "snapshot"
    static let runScene = "runScene"
    static let ok = "ok"
    static let scenes = "scenes"
    static let timers = "timers"
    static let homePads = "homePads"
}

/// A scene the iPhone can run.
struct WatchScene: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
}

/// A timer running on a HomePad.
struct WatchTimer: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let room: String
    let isRunning: Bool
    let end: Date?
    let remaining: TimeInterval
}

/// A HomePad to send intercom messages to.
struct WatchHomePad: Identifiable, Hashable {
    let id: String
    let name: String
}
