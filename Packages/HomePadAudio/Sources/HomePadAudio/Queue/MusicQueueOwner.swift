import Foundation
import HomePadCore

/// Whose queue and place the iPad's music player holds: a household member's
/// own, or the household's when nobody is recognized (guests).
enum MusicQueueOwner: Hashable, Sendable {
    case household
    case member(UUID)

    /// The owner for the person using HomePad now.
    init(memberID: UUID?) {
        self = memberID.map(Self.member) ?? .household
    }

    /// Reads a saved `key`. Nil for an empty or unknown key.
    init?(key: String) {
        if key == Self.householdKey {
            self = .household
        } else if let id = UUID(uuidString: key) {
            self = .member(id)
        } else {
            return nil
        }
    }

    private static let householdKey = "household"

    /// "household", or the member's UUID.
    var key: String {
        switch self {
        case .household: Self.householdKey
        case .member(let id): id.uuidString
        }
    }

    /// Where this owner's music state is saved on this iPad.
    var stateKey: SettingKey<MemberMusicState?> {
        AudioSettings.memberMusicState(ownerKey: key)
    }
}
