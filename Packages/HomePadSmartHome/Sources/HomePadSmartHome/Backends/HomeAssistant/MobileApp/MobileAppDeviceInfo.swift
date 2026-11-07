import Foundation
import HomePadCore
#if canImport(UIKit)
import UIKit
#endif

/// The facts HomePad gives Home Assistant's `mobile_app` integration about this
/// iPad when it registers: the app, the model and the system. Nothing personal.
struct MobileAppDeviceInfo: Equatable, Sendable {
    /// Home Assistant tells registrations apart by this and the device ID together.
    var appID: String
    var appName: String
    var appVersion: String
    var manufacturer: String
    /// The model identifier, such as "iPad16,3".
    var model: String
    var osName: String
    var osVersion: String

    /// This iPad and this build.
    @MainActor
    static var current: MobileAppDeviceInfo {
        let bundle = Bundle.main
        #if canImport(UIKit)
        let device = UIDevice.current
        let osName = device.systemName
        let osVersion = device.systemVersion
        let fallbackModel = device.model
        #else
        let osName = "macOS"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let fallbackModel = "Mac"
        #endif
        return MobileAppDeviceInfo(
            appID: bundle.bundleIdentifier ?? "com.ksha23.homepad",
            appName: "HomePad",
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            manufacturer: "Apple",
            model: modelIdentifier() ?? fallbackModel,
            osName: osName,
            osVersion: osVersion
        )
    }

    /// The hardware model, which `UIDevice.model` does not give ("iPad" only).
    /// The simulator reports the Mac's, so it says which iPad it simulates.
    private static func modelIdentifier() -> String? {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? nil : machine
    }
}

/// What this HomePad is called in Home Assistant, from its room in Devices &
/// Sharing, so each HomePad is its own device there.
enum MobileAppNaming {
    /// "Kitchen HomePad", or "HomePad" before a room is picked.
    static func deviceName(room: String) -> String {
        let trimmed = room.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "HomePad" : "\(trimmed) HomePad"
    }

    /// The notify action Home Assistant makes for the device, without its
    /// domain: `mobile_app_kitchen_homepad`.
    static func notifyService(deviceName: String) -> String {
        HAPlaySoundCall.notifyService(forDeviceNamed: deviceName)
    }
}
