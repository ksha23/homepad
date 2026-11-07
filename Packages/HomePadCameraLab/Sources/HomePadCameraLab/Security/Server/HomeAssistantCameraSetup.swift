import Foundation

/// The exact values for Home Assistant's "MJPEG IP Camera" integration
/// (Settings, Devices and services, Add integration, MJPEG IP Camera).
struct HomeAssistantCameraSetup: Equatable {
    /// This iPad's LAN address, or nil when it is not on a network.
    let host: String?
    let port: Int
    let token: String

    private var base: String? { host.map { "http://\($0):\(port)" } }

    var streamURL: String? { base.map { "\($0)\(MJPEGRoute.streamPath)?token=\(token)" } }
    var snapshotURL: String? { base.map { "\($0)\(MJPEGRoute.snapshotPath)?token=\(token)" } }

    /// Field and value pairs in the order Home Assistant's form asks for them.
    var fields: [(label: String, value: String)] {
        [
            ("Name", "HomePad Camera"),
            ("MJPEG URL", streamURL ?? "Connect to Wi-Fi first"),
            ("Still Image URL", snapshotURL ?? "Connect to Wi-Fi first"),
            ("Username", "Leave empty"),
            ("Password", "Leave empty"),
            ("Verify SSL certificate", "Off"),
        ]
    }
}
