import Foundation
import Observation

/// Which attachments have already been saved to this iPad's Photos, so their download
/// button goes away. Remembered across launches. Attachment ids are unique across chats.
@MainActor
@Observable
final class SavedMedia {
    static let shared = SavedMedia()
    private static let key = "comms.savedAttachments"
    private static let limit = 5000

    private var ids: [String]
    private var lookup: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        ids = saved
        lookup = Set(saved)
    }

    /// True when every attachment in the list is already in Photos.
    func containsAll(_ list: [String]) -> Bool {
        !list.isEmpty && list.allSatisfy { lookup.contains($0) }
    }

    func insert(_ list: [String]) {
        for id in list where lookup.insert(id).inserted { ids.append(id) }
        if ids.count > Self.limit { ids.removeFirst(ids.count - Self.limit); lookup = Set(ids) }
        UserDefaults.standard.set(ids, forKey: Self.key)
    }
}
