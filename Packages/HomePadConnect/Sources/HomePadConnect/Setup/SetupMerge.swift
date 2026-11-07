import Foundation

/// The merge rules for shared documents, the same on every HomePad. Last
/// writer wins per document (`SetupVersion`), deletions included, so the
/// merge is commutative, associative and idempotent and HomePads converge in
/// whatever order documents arrive.
enum SetupMerge {
    /// The document every HomePad keeps of two versions of one.
    static func winner(_ a: SetupDocument, _ b: SetupDocument) -> SetupDocument {
        b.version > a.version ? b : a
    }

    /// Both sets, keeping the winner for each key.
    static func merge(_ local: [SetupKey: SetupDocument], _ incoming: [SetupDocument]) -> [SetupKey: SetupDocument] {
        var merged = local
        for document in incoming {
            merged[document.key] = merged[document.key].map { winner($0, document) } ?? document
        }
        return merged
    }

    /// The versions a HomePad holds, as it tells another in its hello.
    static func manifest(_ documents: [SetupKey: SetupDocument]) -> [SetupKey: SetupVersion] {
        documents.mapValues(\.version)
    }

    /// Documents held here that are newer than another HomePad's, or that it
    /// does not have: what to send it after its hello.
    static func newer(in local: [SetupKey: SetupDocument], than manifest: [SetupKey: SetupVersion]) -> [SetupDocument] {
        local.values
            .filter { document in manifest[document.key].map { document.version > $0 } ?? true }
            .sorted { $0.key < $1.key }
    }
}
