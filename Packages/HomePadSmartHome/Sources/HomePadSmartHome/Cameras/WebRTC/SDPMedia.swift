import Foundation

/// Reads which way each kind of media flows in a session description. The
/// answer settles what a camera does with this offer: whether it sends sound,
/// and whether it takes ours for talking.
struct SDPMedia: Equatable, Sendable {
    enum Direction: String, Sendable {
        case sendrecv, sendonly, recvonly, inactive

        var sends: Bool { self == .sendrecv || self == .sendonly }
        var receives: Bool { self == .sendrecv || self == .recvonly }
    }

    /// Direction of the first m-line of each kind (`audio`, `video`), as the
    /// description's author sees it. A kind refused with port 0 is left out.
    private(set) var directions: [String: Direction] = [:]

    init(sdp: String) {
        var kind: String?
        var direction: Direction = .sendrecv
        func finish() {
            if let kind, directions[kind] == nil { directions[kind] = direction }
        }
        for line in sdp.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("m=") {
                finish()
                let fields = line.dropFirst(2).split(separator: " ")
                // A port of 0 refuses the m-line. Without an attribute a media line is sendrecv.
                kind = fields.count > 1 && fields[1] != "0" ? String(fields[0]) : nil
                direction = .sendrecv
            } else if kind != nil, line.hasPrefix("a="), let value = Direction(rawValue: String(line.dropFirst(2))) {
                direction = value
            }
        }
        finish()
    }

    func direction(of kind: String) -> Direction? { directions[kind] }

    /// The answerer sends sound to us.
    var hasAudio: Bool { directions["audio"]?.sends ?? false }
    var hasVideo: Bool { directions["video"]?.sends ?? false }
    /// The answerer takes our sound: the camera has a speaker on this path.
    var acceptsAudio: Bool { directions["audio"]?.receives ?? false }
}
