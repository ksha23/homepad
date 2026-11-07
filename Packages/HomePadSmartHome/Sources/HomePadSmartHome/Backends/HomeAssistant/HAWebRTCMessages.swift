import Foundation
import HAKit
import HomePadCore

/// What `camera/capabilities` says a camera can stream (Home Assistant 2024.11 and later).
/// `two_way_audio` arrived in 2026.11 as a preview feature, so older servers leave it out.
struct HACameraCapabilities: Equatable, Sendable {
    var streamTypes: Set<String>
    var twoWayAudio: Bool

    var supportsWebRTC: Bool { streamTypes.contains("web_rtc") }
    var supportsHLS: Bool { streamTypes.contains("hls") }

    init(streamTypes: Set<String>, twoWayAudio: Bool = false) {
        self.streamTypes = streamTypes
        self.twoWayAudio = twoWayAudio
    }

    init(json: JSONValue) {
        streamTypes = Set(json["frontend_stream_types"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        twoWayAudio = json["two_way_audio"]?.boolValue ?? false
    }
}

/// `camera/webrtc/get_client_config`: the ICE servers to use, and a data channel
/// label for the few cameras that need one open (Nest).
struct HAWebRTCClientConfig: Equatable, Sendable {
    struct ICEServer: Equatable, Sendable {
        var urls: [String]
        var username: String?
        var credential: String?
    }

    var iceServers: [ICEServer]
    var dataChannel: String?

    init(iceServers: [ICEServer] = [], dataChannel: String? = nil) {
        self.iceServers = iceServers
        self.dataChannel = dataChannel
    }

    init(json: JSONValue) {
        let servers = json["configuration"]?["iceServers"]?.arrayValue ?? []
        iceServers = servers.compactMap { server in
            // The spec allows one URL as a string or several as a list.
            let urls = server["urls"]?.stringValue.map { [$0] } ?? server["urls"]?.arrayValue?.compactMap(\.stringValue) ?? []
            guard !urls.isEmpty else { return nil }
            return ICEServer(urls: urls, username: server["username"]?.stringValue, credential: server["credential"]?.stringValue)
        }
        dataChannel = json["dataChannel"]?.stringValue
    }
}

/// One ICE candidate in the shape of the W3C `RTCIceCandidateInit`, as Home
/// Assistant sends and takes it.
struct HAICECandidate: Equatable, Sendable {
    var candidate: String
    var sdpMid: String?
    var sdpMLineIndex: Int32?

    /// Home Assistant fills in index 0 when go2rtc names neither the mid nor the
    /// index. With BUNDLE every m-line shares one transport, so 0 is right.
    init?(json: JSONValue) {
        guard let candidate = json["candidate"]?.stringValue, !candidate.isEmpty else { return nil }
        self.candidate = candidate
        sdpMid = json["sdpMid"]?.stringValue
        sdpMLineIndex = json["sdpMLineIndex"]?.intValue.map { Int32($0) }
        if sdpMid == nil, sdpMLineIndex == nil { sdpMLineIndex = 0 }
    }

    init(candidate: String, sdpMid: String?, sdpMLineIndex: Int32?) {
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }

    var json: [String: Any] {
        var object: [String: Any] = ["candidate": candidate]
        if let sdpMid { object["sdpMid"] = sdpMid }
        if let sdpMLineIndex { object["sdpMLineIndex"] = Int(sdpMLineIndex) }
        return object
    }
}

/// The events of a `camera/webrtc/offer` subscription, in the order Home
/// Assistant sends them: the session, then the answer and candidates in any order.
enum HAWebRTCEvent: Equatable, Sendable {
    case session(id: String)
    case answer(sdp: String)
    case candidate(HAICECandidate)
    /// Its message can name the camera's address with its password (go2rtc
    /// errors quote the RTSP source), so only the code is ever logged.
    case error(code: String, message: String)

    init?(json: JSONValue) {
        switch json["type"]?.stringValue {
        case "session":
            guard let id = json["session_id"]?.stringValue else { return nil }
            self = .session(id: id)
        case "answer":
            guard let sdp = json["answer"]?.stringValue else { return nil }
            self = .answer(sdp: sdp)
        case "candidate":
            guard let candidate = json["candidate"].flatMap(HAICECandidate.init(json:)) else { return nil }
            self = .candidate(candidate)
        case "error":
            self = .error(code: json["code"]?.stringValue ?? "unknown", message: json["message"]?.stringValue ?? "")
        default:
            return nil
        }
    }
}

extension HARequests {
    static func cameraCapabilities(_ entityID: String) -> HARequest {
        HARequest(type: "camera/capabilities", data: ["entity_id": entityID], shouldRetry: false)
    }

    static func webRTCClientConfig(_ entityID: String) -> HARequest {
        HARequest(type: "camera/webrtc/get_client_config", data: ["entity_id": entityID], shouldRetry: false)
    }

    /// A subscription: Home Assistant answers with events (`HAWebRTCEvent`), and
    /// unsubscribing closes the session. Never retried, because an offer answered
    /// on a new connection would belong to a peer connection that has moved on.
    static func webRTCOffer(_ entityID: String, sdp: String) -> HARequest {
        HARequest(type: "camera/webrtc/offer", data: ["entity_id": entityID, "offer": sdp], shouldRetry: false)
    }

    static func webRTCCandidate(_ entityID: String, sessionID: String, candidate: HAICECandidate) -> HARequest {
        HARequest(type: "camera/webrtc/candidate", data: [
            "entity_id": entityID, "session_id": sessionID, "candidate": candidate.json,
        ], shouldRetry: false)
    }
}
