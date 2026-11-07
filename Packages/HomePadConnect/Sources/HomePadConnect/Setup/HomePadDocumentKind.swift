import Foundation

/// How a HomePad's own document (Core's `HomePadDocumentDescriptor`) travels in
/// the shared setup: as a household document whose kind also names the
/// HomePad, `<kind>@<device ID>`, for example
/// `smarthome.homeKitDirectory@<UUID>/household`.
///
/// Each HomePad writes only the one with its own device ID, so the last
/// writer rule never has two HomePads competing for one document. A HomePad
/// from before these documents reads the key as usual and leaves it out as a
/// kind it does not know.
enum HomePadDocumentKind {
    static func make(_ kind: String, homePad: String) -> String {
        "\(kind)@\(homePad)"
    }

    /// The descriptor's kind and the HomePad's device ID, or nil for a kind
    /// that is not a HomePad's own.
    static func split(_ kind: String) -> (kind: String, homePad: String)? {
        guard let at = kind.lastIndex(of: "@") else { return nil }
        let base = String(kind[..<at])
        let homePad = String(kind[kind.index(after: at)...])
        guard !base.isEmpty, !homePad.isEmpty else { return nil }
        return (base, homePad)
    }
}
