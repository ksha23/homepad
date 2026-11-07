import HomePadCore
import HomePadUI
import PhotosUI
import SwiftUI

/// Pick the frosted face, a curated gradient or one photo (system photo picker,
/// no library permission needed) as this member's Home Screen wallpaper.
///
/// The system photo picker browses the iPad's whole library, so it is offered
/// only while the library's owner is recognized (`PhotoAccessPolicy`). Anyone
/// else keeps a photo wallpaper they already have.
struct WallpaperPickerSheet: View {
    let memberID: HouseholdMember.ID?
    let accent: Color
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings
    @Environment(WallpaperPhotoStore.self) private var photos
    @State private var pickedItem: PhotosPickerItem?
    @State private var photoFailed = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.l)]

    var body: some View {
        let selected = settings[ShellSettings.wallpaper(for: memberID)]
        // A choice applies at once, so the sheet only closes.
        SheetScreen("Wallpaper") {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                    Button {
                        settings[ShellSettings.wallpaper(for: memberID)] = .face
                    } label: {
                        swatch(FaceSwatch(), title: WallpaperChoice.face.title, isSelected: selected == .face)
                    }
                    .buttonStyle(.plain)
                    ForEach(WallpaperChoice.gradients) { choice in
                        Button {
                            settings[ShellSettings.wallpaper(for: memberID)] = choice
                        } label: {
                            swatch(WallpaperBackground(choice: choice, accent: accent, photo: nil),
                                   title: choice.title, isSelected: selected == choice)
                        }
                        .buttonStyle(.plain)
                    }
                    if services.photoAccess.allowsLibrary {
                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            swatch(photoSwatch, title: "Photo", isSelected: selected == .photo)
                        }
                        .buttonStyle(.plain)
                    } else if photos.image(for: memberID) != nil {
                        Button {
                            settings[ShellSettings.wallpaper(for: memberID)] = .photo
                        } label: {
                            swatch(photoSwatch, title: "Photo", isSelected: selected == .photo)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.l)
                if photoFailed {
                    Text("That photo could not be used. Try another one.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await usePhoto(item) }
        }
    }

    @ViewBuilder
    private var photoSwatch: some View {
        if let image = photos.image(for: memberID) {
            WallpaperBackground(choice: .photo, accent: accent, photo: image)
        } else {
            ZStack {
                Color.primary.opacity(0.08)
                Image(systemName: "photo.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
    }

    private func swatch(_ fill: some View, title: String, isSelected: Bool) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            fill
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(isSelected ? Color.primary : .primary.opacity(0.15), lineWidth: isSelected ? 4 : 1)
                }
            Text(title).font(.headline)
        }
        // The whole card takes the tap. The Face swatch's live face takes no
        // touches, which left only its border and title tappable.
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func usePhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), photos.save(data, for: memberID) else {
            photoFailed = true
            return
        }
        photoFailed = false
        settings[ShellSettings.wallpaper(for: memberID)] = .photo
    }
}

/// A live, scaled-down copy of the current face behind the frost, laid out at
/// screen size first so it looks like the real Home Screen.
private struct FaceSwatch: View {
    private let reference = CGSize(width: 1366, height: 1024)

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / reference.width, proxy.size.height / reference.height)
            ZStack {
                CurrentFaceView()
                FaceFrost()
            }
            .frame(width: reference.width, height: reference.height)
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .allowsHitTesting(false)
        }
    }
}
