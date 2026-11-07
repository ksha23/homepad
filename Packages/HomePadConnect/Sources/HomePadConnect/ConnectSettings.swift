import Foundation
import HomePadCore

/// Settings owned by the Connect module.
public enum ConnectSettings {
    // Identity on the peer link. Device-local, never synced.
    static let deviceID = SettingKey<String>("connect.deviceID", default: "")
    /// The room this HomePad lives in ("Kitchen"). Used for "Intercom from Kitchen",
    /// and by Home Assistant for this HomePad's name, so it lives in Core.
    public static let roomName = CoreSettings.roomName
    public static let linkEnabled = SettingKey<Bool>("connect.link.enabled", default: true)
    /// The household this HomePad hosts: it showed a pairing code for it, the
    /// first of which made the household's key. Its setup wins when two
    /// HomePads first share one (`SetupStanding`).
    static let hostedHousehold = SettingKey<String>("connect.setup.hostedHousehold", default: "")

    // Intercom.
    public static let intercomAutoPlay = SettingKey<Bool>("connect.intercom.autoPlay", default: true)
    public static let intercomQuietAtNight = SettingKey<Bool>("connect.intercom.quietAtNight", default: true)
    public static let intercomSpeakText = SettingKey<Bool>("connect.intercom.speakText", default: true)
    /// One of `IntercomHub.clipLengths`.
    public static let intercomMaxSeconds = SettingKey<Double>("connect.intercom.maxSeconds", default: 20)

    // Alert relay.
    public static let relayedAlerts = SettingKey<[RelayedAlert]>("connect.alerts.relayed", default: RelayedAlert.allCases, syncsWithICloud: true)
    /// Home Assistant notify service, for example "notify.mobile_app_your_iphone". Empty disables it.
    public static let alertNotifyService = SettingKey<String>("connect.alerts.haNotifyService", default: "", syncsWithICloud: true)

    // Handoff.
    public static let handoffRecipes = SettingKey<Bool>("connect.handoff.recipes", default: true)
    public static let handoffNowPlaying = SettingKey<Bool>("connect.handoff.nowPlaying", default: true)
    public static let handoffAssistant = SettingKey<Bool>("connect.handoff.assistant", default: true)

    // Family Board.
    public static let boardICloudSync = SettingKey<Bool>("connect.board.iCloud", default: true)

    // Companion music. Device-local: what this phone searched for on HomePads, newest first.
    public static let musicRecentSearches = SettingKey<[String]>("connect.music.recentSearches", default: [])

    // Shortcuts app.
    public static let shortcutNames = SettingKey<[String]>("connect.shortcuts.names", default: [], syncsWithICloud: true)
}

/// The fixed set of alerts the relay can forward. Curated, not free-form.
public enum RelayedAlert: String, Codable, CaseIterable, Sendable, Identifiable {
    case smoke, carbonMonoxide, doorbell

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smoke: "Smoke Alarm"
        case .carbonMonoxide: "Carbon Monoxide Alarm"
        case .doorbell: "Doorbell"
        }
    }

    public var systemImage: String {
        switch self {
        case .smoke: "smoke.fill"
        case .carbonMonoxide: "carbon.monoxide.cloud.fill"
        case .doorbell: "bell.fill"
        }
    }

    /// Maps a sound-classifier label (for example "smoke_alarm") to an alert.
    public init?(soundLabel: String) {
        let label = soundLabel.lowercased()
        if label.contains("smoke") || label.contains("fire_alarm") {
            self = .smoke
        } else if label.contains("carbon") || label == "co" || label.hasPrefix("co_") {
            self = .carbonMonoxide
        } else if label.contains("doorbell") {
            self = .doorbell
        } else {
            return nil
        }
    }
}
