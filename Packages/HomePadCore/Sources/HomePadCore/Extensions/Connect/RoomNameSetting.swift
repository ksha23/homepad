import Foundation

public extension CoreSettings {
    /// The room this HomePad lives in ("Kitchen"), picked in Settings > Devices &
    /// Sharing. Other HomePads and Home Assistant know this HomePad by it. Not
    /// synced, so each HomePad keeps its own. Connect owns the setting, and the
    /// key keeps Connect's name so saved rooms still load.
    static let roomName = SettingKey<String>("connect.roomName", default: "")
}
