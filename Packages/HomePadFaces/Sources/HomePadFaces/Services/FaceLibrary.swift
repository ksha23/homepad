import Foundation
import HomePadCore
import Observation

/// Whose saved faces a list belongs to.
enum FaceOwner: Codable, Hashable, Sendable {
    case household
    case member(UUID)

    var key: String {
        switch self {
        case .household: "household"
        case .member(let id): id.uuidString
        }
    }
}

/// A list of saved faces and which one is showing, like the Watch app's "My Faces".
struct SavedFaceList: Codable, Hashable, Sendable {
    var faces: [FaceConfiguration]
    var currentID: UUID?
}

/// Saved face configurations for the household and for each member.
///
/// A member without a list of their own sees the household list. The first
/// edit copies it into their own. The current face is mirrored into the
/// shared Core settings so the shell knows which face kind to show:
/// `CoreSettings.defaultFaceID` for the household and
/// `member.preferences["faceID"]` for a member.
@MainActor
@Observable
final class FaceLibrary {
    /// Shared with the household's other HomePads by Connect (`FaceSharing`), not through iCloud.
    static let storageKey = SettingKey<[String: SavedFaceList]>("faces.library", default: [:])
    static let memberPreferenceKey = HouseholdMember.facePreferenceKey

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let household: Household
    @ObservationIgnored private var cache: [String: SavedFaceList] = [:]
    @ObservationIgnored private var cacheRevision = -1

    init(settings: SettingsStore, household: Household) {
        self.settings = settings
        self.household = household
    }

    // MARK: Reading

    /// The owner whose faces show right now: the active member when they have
    /// their own list, otherwise the household.
    var activeOwner: FaceOwner {
        if let member = household.activeMember, stored[member.id.uuidString] != nil {
            return .member(member.id)
        }
        return .household
    }

    /// The saved faces for an owner. Members without their own list get the household's.
    func list(for owner: FaceOwner) -> SavedFaceList {
        if let list = stored[owner.key], !list.faces.isEmpty { return list }
        if case .member = owner { return list(for: .household) }
        return Self.defaultList
    }

    /// True when the owner has saved faces of their own.
    func hasOwnList(_ owner: FaceOwner) -> Bool {
        stored[owner.key] != nil
    }

    /// The face showing for an owner. Follows the shared face ID when another
    /// module (the shell's settings) changed it.
    func current(for owner: FaceOwner) -> FaceConfiguration {
        let list = list(for: owner)
        let wanted = sharedFaceID(for: owner)
        if let id = list.currentID, let face = list.faces.first(where: { $0.id == id }),
           wanted == nil || face.faceID == wanted {
            return face
        }
        if let wanted {
            return list.faces.first { $0.faceID == wanted } ?? .unsaved(wanted)
        }
        return list.faces.first ?? .unsaved(FaceCatalog.defaultFaceID)
    }

    /// The configuration to draw a face kind with: the current face when it is
    /// that kind, else the first saved face of that kind, else its defaults.
    func configuration(forFace faceID: String, owner: FaceOwner) -> FaceConfiguration {
        let current = current(for: owner)
        if current.faceID == faceID { return current }
        return list(for: owner).faces.first { $0.faceID == faceID } ?? .unsaved(faceID)
    }

    // MARK: Editing

    /// Adds a new face of a kind with default choices and returns it.
    @discardableResult
    func add(faceID: String, to owner: FaceOwner) -> FaceConfiguration {
        let face = FaceConfiguration(faceID: faceID)
        mutate(owner) { $0.faces.append(face) }
        return face
    }

    /// Saves changes to a face, or adds it when it is new.
    func save(_ face: FaceConfiguration, for owner: FaceOwner) {
        mutate(owner) { list in
            if let index = list.faces.firstIndex(where: { $0.id == face.id }) {
                list.faces[index] = face
            } else {
                list.faces.append(face)
            }
        }
    }

    /// Removes a saved face. The last face cannot be removed.
    func remove(_ id: UUID, from owner: FaceOwner) {
        guard list(for: owner).faces.count > 1 else { return }
        mutate(owner) { list in
            list.faces.removeAll { $0.id == id }
            if list.currentID == id { list.currentID = list.faces.first?.id }
        }
        publishCurrent(for: owner)
    }


    /// Shows a saved face from now on. The face on the wall makes the face a
    /// swipe lands on current (`FacePager`).
    func makeCurrent(_ id: UUID, for owner: FaceOwner) {
        mutate(owner) { $0.currentID = id }
        publishCurrent(for: owner)
    }

    // MARK: Sharing with the household's other HomePads

    /// An owner's own list as HomePads share it, nil when they have none.
    /// Photos picked from this iPad's library stay out (`FacePhotoPicks`).
    func sharedList(for owner: FaceOwner) -> SavedFaceList? {
        guard var list = stored[owner.key] else { return nil }
        list.faces = list.faces.map(FacePhotoPicks.removing)
        return list
    }

    /// Saves a list another HomePad shared and shows its current face. A face
    /// this iPad already has keeps its own photo picks. Nil takes away the
    /// owner's own list: a person then sees the household's, and the
    /// household its defaults.
    func applyShared(_ list: SavedFaceList?, for owner: FaceOwner) {
        var all = stored
        if var list {
            let local = all[owner.key]?.faces ?? []
            list.faces = list.faces.map { face in
                local.first { $0.id == face.id }.map { FacePhotoPicks.keeping($0, in: face) } ?? face
            }
            all[owner.key] = list
        } else {
            all[owner.key] = nil
        }
        settings[Self.storageKey] = all
        if all[owner.key] != nil {
            publishCurrent(for: owner)
        } else if case .member(let memberID) = owner,
                  var member = household.members.first(where: { $0.id == memberID }),
                  member.preferences[Self.memberPreferenceKey] != nil {
            // Back on the household's list, the person follows the household's current face.
            member.preferences[Self.memberPreferenceKey] = nil
            household.update(member)
        }
    }

    /// Gives a person's list the ID the household knows them by, as this
    /// HomePad joins its setup. Where the household has its own list for
    /// them, that replaces this one right after.
    func moveOwner(from old: UUID, to new: UUID) {
        var all = stored
        guard let list = all.removeValue(forKey: FaceOwner.member(old).key) else { return }
        all[FaceOwner.member(new).key] = list
        settings[Self.storageKey] = all
    }

    // MARK: Storage

    private var stored: [String: SavedFaceList] {
        if cacheRevision != settings.revision {
            cache = settings[Self.storageKey]
            cacheRevision = settings.revision
        }
        return cache
    }

    private func mutate(_ owner: FaceOwner, _ change: (inout SavedFaceList) -> Void) {
        var all = stored
        var list = all[owner.key] ?? list(for: owner)
        change(&list)
        all[owner.key] = list
        settings[Self.storageKey] = all
    }

    /// Mirrors the current face kind into the settings the shell reads.
    private func publishCurrent(for owner: FaceOwner) {
        guard let id = list(for: owner).currentID,
              let face = list(for: owner).faces.first(where: { $0.id == id }) else { return }
        switch owner {
        case .household:
            settings[CoreSettings.defaultFaceID] = face.faceID
        case .member(let memberID):
            guard var member = household.members.first(where: { $0.id == memberID }) else { return }
            member.preferences[Self.memberPreferenceKey] = .string(face.faceID)
            household.update(member)
        }
    }

    private func sharedFaceID(for owner: FaceOwner) -> String? {
        switch owner {
        case .household:
            return settings[CoreSettings.defaultFaceID]
        case .member(let memberID):
            return household.members.first { $0.id == memberID }?.preferences[Self.memberPreferenceKey]?.stringValue
        }
    }

    // MARK: Defaults

    /// The faces a new HomePad starts with. They look good without any setup.
    static let defaultList = SavedFaceList(
        faces: [
            preset(1, "faces.modular"),
            preset(2, "faces.photos"),
            preset(3, "faces.homeModular"),
            preset(4, "faces.numerals"),
            preset(5, "faces.weather"),
            preset(6, "faces.flow"),
            preset(7, "faces.calendar"),
            preset(8, "faces.critters"),
            preset(9, "faces.analog"),
            preset(10, "faces.night"),
        ],
        currentID: presetID(1)
    )

    private static func preset(_ number: Int, _ faceID: String) -> FaceConfiguration {
        FaceConfiguration(id: presetID(number), faceID: faceID)
    }

    private static func presetID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "FACE0000-0000-4000-8000-%012d", number)) ?? UUID()
    }
}
