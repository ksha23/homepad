import Foundation
import HomePadCore

/// The Home Screens HomePads in one household share (Core's
/// `SharedDocumentDescriptor`, carried by Connect): each person's layout and
/// the guest layout, with pages, apps, widgets, stacks, widget settings and the
/// header's mini widget, and each person's and the guest wallpaper.
///
/// A layout is saved as logical pages, not positions on a screen, so it lands
/// on each iPad's own grid: six columns in landscape and four in portrait
/// everywhere, and as many rows as the screen holds. A page with more than one
/// screen holds goes on to the next screen there (`HomeScreenPages.render`).
///
/// A widget with Same on All HomePads off keeps its own settings on each
/// iPad (Core's `WidgetSettingsOnEachHomePad.swift`). The layout carries the
/// settings it had when the switch was turned off, which an older HomePad shows.
///
/// A photo wallpaper is a picture from one iPad's library, so it stays on that
/// iPad. The other HomePads keep the wallpaper they had, and a gradient or
/// Face chosen anywhere later replaces it.
@MainActor
enum HomeScreenSharing {
    static let layoutKind = "shell.homeScreen"
    static let wallpaperKind = "shell.wallpaper"

    static func register(services: AppServices, in registry: ModuleRegistry) {
        let settings = services.settings
        registry.register(sharedDocument: SharedDocumentDescriptor(
            id: layoutKind, owners: [.household, .members],
            read: { readLayout($0, settings: settings) },
            apply: { applyLayout($1, for: $0, settings: settings) }
        ))
        registry.register(sharedDocument: SharedDocumentDescriptor(
            id: wallpaperKind, owners: [.household, .members],
            read: { readWallpaper($0, settings: settings) },
            apply: { applyWallpaper($1, for: $0, settings: settings) }
        ))
        services.household.onMemberIDChange { old, new in
            moveMember(from: old, to: new, settings: settings)
        }
    }

    // MARK: Layouts

    /// The saved layout, as saved: apps registered since show on screen but
    /// are not part of it. A widget with Same on All HomePads off carries the
    /// shared copy of its settings, not this iPad's own.
    static func readLayout(_ owner: SharedDocumentOwner, settings: SettingsStore) -> SharedDocumentValue {
        let key = ShellSettings.homeScreenLayout(for: owner.memberID)
        guard settings.contains(key), let layout = settings[key],
              let content = try? JSONValue(encoding: layout) else { return .none }
        return .content(content.sharingWidgetSettings())
    }

    /// Saves a shared layout, or goes back to the default for nil. A widget
    /// with Same on All HomePads off keeps this iPad's own settings.
    static func applyLayout(_ content: JSONValue?, for owner: SharedDocumentOwner, settings: SettingsStore) {
        let key = ShellSettings.homeScreenLayout(for: owner.memberID)
        guard let content else {
            settings.reset(key)
            return
        }
        let local = settings[key].flatMap { try? JSONValue(encoding: $0) }
        let kept = content.keepingOwnWidgetSettings(from: local)
        guard let layout = try? kept.decoded(as: HomeScreenLayout.self) else { return }
        settings[key] = layout
    }

    // MARK: Wallpapers

    static func readWallpaper(_ owner: SharedDocumentOwner, settings: SettingsStore) -> SharedDocumentValue {
        let key = ShellSettings.wallpaper(for: owner.memberID)
        guard settings.contains(key) else { return .none }
        let choice = settings[key]
        if choice == .photo { return .onlyThisHomePad }
        guard let content = try? JSONValue(encoding: choice) else { return .none }
        return .content(content)
    }

    static func applyWallpaper(_ content: JSONValue?, for owner: SharedDocumentOwner, settings: SettingsStore) {
        let key = ShellSettings.wallpaper(for: owner.memberID)
        guard let content else {
            settings.reset(key)
            return
        }
        // A photo is never shared, since it names a picture on another iPad.
        guard let choice = try? content.decoded(as: WallpaperChoice.self), choice != .photo else { return }
        settings[key] = choice
    }

    // MARK: A person's new ID

    /// Moves a person's layout, wallpaper and wallpaper photo to the ID the
    /// household knows them by, as this HomePad joins its setup. Where the
    /// household has its own for them, that replaces these right after.
    static func moveMember(from old: UUID, to new: UUID, settings: SettingsStore,
                           photos: WallpaperPhotoStore.Files = .standard) {
        settings.moveValue(fromKeyNamed: ShellSettings.homeScreenLayout(for: old).name,
                           toKeyNamed: ShellSettings.homeScreenLayout(for: new).name)
        settings.moveValue(fromKeyNamed: ShellSettings.wallpaper(for: old).name,
                           toKeyNamed: ShellSettings.wallpaper(for: new).name)
        photos.move(from: old, to: new)
    }
}
