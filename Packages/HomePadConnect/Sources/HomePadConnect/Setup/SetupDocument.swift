import Foundation
import HomePadCore

/// Names one shared document: its kind and whose it is, written
/// `shell.homeScreen/household` or `core.member/<member UUID>`.
struct SetupKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// The kind for the household's people, which Connect shares itself.
    static let memberKind = "core.member"

    let kind: String
    let owner: SharedDocumentOwner

    init(kind: String, owner: SharedDocumentOwner) {
        self.kind = kind
        self.owner = owner
    }

    /// Reads `kind/owner`. Nil for anything else.
    init?(_ text: String) {
        guard let slash = text.lastIndex(of: "/"),
              let owner = SharedDocumentOwner(key: String(text[text.index(after: slash)...])) else { return nil }
        self.init(kind: String(text[..<slash]), owner: owner)
    }

    static func member(_ id: UUID) -> SetupKey {
        SetupKey(kind: memberKind, owner: .member(id))
    }

    var description: String { "\(kind)/\(owner.key)" }

    static func < (lhs: SetupKey, rhs: SetupKey) -> Bool {
        lhs.description < rhs.description
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let key = SetupKey(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a setup key: \(text)"))
        }
        self = key
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// The version of one shared document: how many times it changed, and the
/// device and time of its last change.
///
/// The last writer wins: the later time, then the higher number, then the
/// higher device ID, so every HomePad picks the same one. A change made after
/// seeing a version is always stamped later than it (`next(after:device:now:)`),
/// even when this iPad's clock is behind, so it never loses to what it replaced.
struct SetupVersion: Codable, Hashable, Comparable, Sendable {
    var number: Int
    /// Whole milliseconds since 1970, so a version reads back exactly as it was written.
    var time: Int64
    /// The peer-link device ID of the HomePad that made the change.
    var device: String

    var date: Date { Date(timeIntervalSince1970: TimeInterval(time) / 1000) }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    /// The version for a change on `device` at `now` to a document last at `previous`.
    static func next(after previous: SetupVersion?, device: String, now: Date) -> SetupVersion {
        let floor = previous.map { $0.time + 1 } ?? 0
        return SetupVersion(number: (previous?.number ?? 0) + 1, time: max(milliseconds(now), floor), device: device)
    }

    static func < (lhs: SetupVersion, rhs: SetupVersion) -> Bool {
        (lhs.time, lhs.number, lhs.device) < (rhs.time, rhs.number, rhs.device)
    }
}

/// One shared document at one version. Nil content is a deletion (a tombstone),
/// kept so the deletion reaches a HomePad that was off when it happened.
struct SetupDocument: Codable, Equatable, Sendable {
    var key: SetupKey
    var version: SetupVersion
    var content: JSONValue?

    var isDeleted: Bool { content == nil }
}
