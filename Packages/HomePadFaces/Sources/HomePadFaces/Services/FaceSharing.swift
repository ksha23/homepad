import Foundation
import HomePadCore

/// The faces HomePads in one household share (Core's `SharedDocumentDescriptor`,
/// carried by Connect): each owner's saved faces with every option, widget
/// layout, stack and mini widget, which face is current, and the Smart
/// Rotation rules. They used to go through iCloud key-value storage, which
/// reaches only one Apple Account and knows nothing of the household's people.
///
/// A face's widgets are saved by cell on a grid with the same columns and
/// rows on every iPad (`FaceGrid`), so a layout keeps its arrangement on an 11
/// and a 13 inch iPad. Each iPad works out which cells its face's own content
/// needs at its size (`FaceGrid.blocked`), and a widget that has no room there
/// steps down or waits, without changing what was saved (`FaceWidgetBoard`).
///
/// A face widget with Same on All HomePads off keeps its own settings on each
/// iPad (Core's `WidgetSettingsOnEachHomePad.swift`), and so does each widget
/// in a stack whose switch is off.
@MainActor
enum FaceSharing {
    static let libraryKind = "faces.library"
    static let rotationKind = "faces.rotation"

    static func register(runtime: FacesRuntime, services: AppServices, in registry: ModuleRegistry) {
        let settings = services.settings
        // Shared by the household now. An older HomePad on the same Apple Account may still write these to iCloud.
        for name in [FaceLibrary.storageKey.name, RotationStore.storageKey.name, CoreSettings.defaultFaceID.name] {
            settings.stopICloudSync(forKeyNamed: name)
        }
        let library = runtime.library
        registry.register(sharedDocument: SharedDocumentDescriptor(
            id: libraryKind, owners: [.household, .members],
            read: { readLibrary(FaceOwner($0), library: library) },
            apply: { applyLibrary($1, for: FaceOwner($0), library: library) }
        ))
        registry.register(sharedDocument: SharedDocumentDescriptor(
            id: rotationKind, owners: .household,
            read: { _ in
                guard settings.contains(RotationStore.storageKey),
                      let content = try? JSONValue(encoding: settings[RotationStore.storageKey]) else { return .none }
                return .content(content)
            },
            apply: { _, content in
                guard let content else { return settings.reset(RotationStore.storageKey) }
                guard let rules = try? content.decoded(as: RotationSettings.self) else { return }
                settings[RotationStore.storageKey] = rules
            }
        ))
        services.household.onMemberIDChange { old, new in library.moveOwner(from: old, to: new) }
    }

    // MARK: Saved faces

    /// An owner's own faces as HomePads share them (`FaceLibrary.sharedList`).
    /// A widget with Same on All HomePads off carries the shared copy of its
    /// settings, not this iPad's own.
    static func readLibrary(_ owner: FaceOwner, library: FaceLibrary) -> SharedDocumentValue {
        guard let list = library.sharedList(for: owner),
              let content = try? JSONValue(encoding: list) else { return .none }
        return .content(content.sharingWidgetSettings())
    }

    /// Saves faces another HomePad shared (`FaceLibrary.applyShared`). A
    /// widget with Same on All HomePads off keeps this iPad's own settings,
    /// from the faces this iPad shows for the owner now, which for a person
    /// with no faces of their own yet are the household's.
    static func applyLibrary(_ content: JSONValue?, for owner: FaceOwner, library: FaceLibrary) {
        guard let content else { return library.applyShared(nil, for: owner) }
        let local = try? JSONValue(encoding: library.list(for: owner))
        let kept = content.keepingOwnWidgetSettings(from: local)
        guard let list = try? kept.decoded(as: SavedFaceList.self) else { return }
        library.applyShared(list, for: owner)
    }
}

extension FaceOwner {
    init(_ owner: SharedDocumentOwner) {
        switch owner {
        case .household: self = .household
        case .member(let id): self = .member(id)
        }
    }
}

/// What a Photos face picked from this iPad's photo library: an album, single
/// photos or one photo with its framing. They name photos by this iPad's
/// identifiers, so they stay on it. The source kind is shared, so a face set
/// to an album here shows that kind on the other HomePads, where someone picks
/// the album from their library.
enum FacePhotoPicks {
    static let valueKeys = [PhotoSourcePage.albumIDKey, PhotoSourcePage.albumTitleKey, PhotoSourcePage.singleKey,
                            PhotoFraming.zoomKey, PhotoFraming.centerXKey, PhotoFraming.centerYKey]
    static let itemKeys = [PhotoSourcePage.pickedKey]

    /// The face without this iPad's picks.
    static func removing(from face: FaceConfiguration) -> FaceConfiguration {
        var face = face
        valueKeys.forEach { face.values[$0] = nil }
        itemKeys.forEach { face.items[$0] = nil }
        return face
    }

    /// `shared` with the picks `local`, the same face on this iPad, has.
    static func keeping(_ local: FaceConfiguration, in shared: FaceConfiguration) -> FaceConfiguration {
        var face = shared
        valueKeys.forEach { face.values[$0] = local.values[$0] }
        itemKeys.forEach { face.items[$0] = local.items[$0] }
        return face
    }
}
