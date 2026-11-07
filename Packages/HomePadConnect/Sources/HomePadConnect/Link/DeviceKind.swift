import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What sort of device sits at the other end of the peer link.
public enum DeviceKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// An iPad running the always-on HomePad shell.
    case homePad
    /// The iPhone companion.
    case iPhone
    /// The Mac companion ("Designed for iPad").
    case mac

    /// The kind of the device this code runs on.
    @MainActor
    public static var current: DeviceKind {
        #if canImport(UIKit)
        if ProcessInfo.processInfo.isiOSAppOnMac { return .mac }
        return UIDevice.current.userInterfaceIdiom == .pad ? .homePad : .iPhone
        #else
        return .mac
        #endif
    }

    /// Companions send and control. HomePads receive and play.
    public var isCompanion: Bool { self != .homePad }

    public var systemImage: String {
        switch self {
        case .homePad: "ipad.landscape"
        case .iPhone: "iphone"
        case .mac: "laptopcomputer"
        }
    }

    public var displayName: String {
        switch self {
        case .homePad: "HomePad"
        case .iPhone: "iPhone"
        case .mac: "Mac"
        }
    }
}
