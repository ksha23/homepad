import Foundation
import HomePadCore

/// What a notification from Home Assistant asks of this HomePad.
///
/// Home Assistant's `notify.mobile_app_<device>` delivers `message`, `title`
/// and `data` over the push channel. A message that names a command runs it,
/// with its options in `data`. The Home Assistant app's kiosk commands work
/// where HomePad has the same thing, and HomePad adds its own. Any other
/// message is shown as a banner.
enum MobileAppCommand: Equatable {
    /// `kiosk_show_screensaver`: the screen sleeps, a dim drifting clock.
    case sleep
    /// `kiosk_hide_screensaver`: the screen wakes.
    case wake
    /// `kiosk_show_camera` with `entity_id`: that camera full screen.
    case showCamera(entityID: String)
    /// `kiosk_hide_camera`: closes a camera that is full screen.
    case hideCamera
    /// `kiosk_set_brightness` with `level` from 0 to 100, as a fraction.
    case setBrightness(Double)
    /// `kiosk_set_volume` with `volume` from 0 to 100, as a fraction.
    case setVolume(Double)
    /// `kiosk_reload`: loads Home Assistant's states and registries again.
    case reload
    /// `kiosk_default`: back to the usual face.
    case showDefaultFace
    /// `homepad_show_face`, with `face` (an ID or a name) or the face showing.
    case showFace(String?)
    /// `homepad_go_home`: the Home Screen.
    case goHome
    /// `homepad_open_app` with `app` (an ID or a name).
    case openApp(String)
    /// `homepad_speak` with `text`, in the assistant's voice.
    case speak(String, title: String?)
    /// Anything else: a banner with the title and message.
    case banner(title: String?, message: String)
    /// Nothing to do, and why, for the log.
    case ignored(String)

    /// Reads one push channel event: `{"message", "title", "data"}`.
    static func parse(_ event: JSONValue) -> MobileAppCommand {
        let message = (event["message"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = event["title"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        let data = event["data"] ?? .null
        switch message {
        case "kiosk_show_screensaver": return .sleep
        case "kiosk_hide_screensaver": return .wake
        case "kiosk_show_camera":
            guard let entity = data["entity_id"]?.stringValue, entity.hasPrefix("camera.") else {
                return .ignored("kiosk_show_camera needs a camera entity_id")
            }
            return .showCamera(entityID: entity)
        case "kiosk_hide_camera": return .hideCamera
        case "kiosk_set_brightness":
            return percent(data["level"]).map(MobileAppCommand.setBrightness)
                ?? .ignored("kiosk_set_brightness needs a level from 0 to 100")
        case "kiosk_set_volume":
            return percent(data["volume"]).map(MobileAppCommand.setVolume)
                ?? .ignored("kiosk_set_volume needs a volume from 0 to 100")
        case "kiosk_reload": return .reload
        case "kiosk_default": return .showDefaultFace
        case "kiosk_set_screensaver_mode", "kiosk_set_screensaver_brightness":
            return .ignored("\(message) has no HomePad equivalent: the sleeping screen is always a dim clock")
        case "homepad_show_face": return .showFace(text(data["face"]))
        case "homepad_go_home": return .goHome
        case "homepad_open_app":
            return text(data["app"]).map(MobileAppCommand.openApp) ?? .ignored("homepad_open_app needs an app")
        case "homepad_speak":
            return text(data["text"]).map { .speak($0, title: title) } ?? .ignored("homepad_speak needs a text")
        default:
            break
        }
        if message.hasPrefix("kiosk_") || message.hasPrefix("homepad_") {
            return .ignored("\(message) is not a command HomePad knows")
        }
        if companionMessages.contains(message) {
            return .ignored("\(message) is for the Home Assistant app")
        }
        guard !message.isEmpty else { return .ignored("an empty notification") }
        return .banner(title: title, message: message)
    }

    /// Messages Home Assistant sends every phone app to ask for something
    /// rather than to show, which would otherwise read as a banner.
    static let companionMessages: Set<String> = [
        "request_location_update", "clear_notification", "clear_badge",
        "update_complications", "update_widgets",
    ]

    /// A 0 to 100 number (or numeric text) as a fraction from 0 to 1.
    private static func percent(_ value: JSONValue?) -> Double? {
        guard let number = value?.doubleValue, number.isFinite else { return nil }
        return min(max(number, 0), 100) / 100
    }

    private static func text(_ value: JSONValue?) -> String? {
        let trimmed = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
