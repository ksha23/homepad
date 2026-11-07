import HomePadCore
import PhotosUI
import SwiftUI

/// Whose photo library this iPad holds, and which photos feed the slideshow
/// and the Photo widget.
///
/// The library's own albums, the system photo picker and Allow More Photos
/// show only while the owner is recognized (`PhotoAccessPolicy`), so another
/// admin never browses someone else's library from Settings.
struct PhotoSourcesSection: View {
    @Environment(PhotoLibraryService.self) private var photos
    @Environment(SettingsStore.self) private var settings
    @Environment(AppServices.self) private var services
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        let access = services.photoAccess
        Section {
            ownerPicker
            if photos.canShowPhotos {
                Toggle("All Photos in the Library", isOn: binding(\.includeLibrary))
                Toggle("Favorites", isOn: binding(\.includeFavorites))
                Toggle("Shared Albums", isOn: binding(\.includeSharedAlbums))
                if access.allowsLibrary {
                    ForEach(photos.albums.filter { $0.kind == .user }) { album in
                        Toggle(album.title, isOn: albumBinding(album.id))
                    }
                    if !photos.isUsingDemoData {
                        let pickedCount = settings[PersonalSettings.photoSources].pickedPhotoIDs.count
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 200, selectionBehavior: .ordered, matching: .images, photoLibrary: .shared()) {
                            LabeledContent("Selected Photos", value: "\(pickedCount)")
                        }
                    }
                    if photos.isLimited {
                        Button("Allow More Photos") { photos.chooseAllowedPhotos() }
                    }
                } else {
                    Text("Albums and photos from \(ownerName)'s library can be chosen here while \(ownerName) is recognized.")
                        .foregroundStyle(.secondary)
                }
                Picker("Slideshow Speed", selection: settings.binding(PersonalSettings.slideshowInterval)) {
                    Text("Fast").tag(5.0)
                    Text("Normal").tag(8.0)
                    Text("Relaxed").tag(15.0)
                    Text("Slow").tag(30.0)
                }
            } else if access.allowsLibrary {
                Button("Allow Photos Access") { Task { await photos.requestAccess() } }
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("This iPad's photo library belongs to its owner, who sees all of it in Photos while recognized. Everyone else in the household sees the Shared Albums. The slideshow and the Photo widget show the photos chosen here to whoever is in the room, and the whole library when nothing chosen has photos.")
        }
        .task { photos.reload() }
        .onChange(of: pickerItems) {
            photos.setPickedPhotos(pickerItems.compactMap(\.itemIdentifier))
        }
    }

    /// The member whose Apple Account the library belongs to: the first admin
    /// until someone picks another.
    @ViewBuilder
    private var ownerPicker: some View {
        let members = services.household.members
        if !members.isEmpty {
            Picker("Photo Library Owner", selection: Binding(
                get: { services.photoLibraryOwnerID },
                set: { settings[PhotoLibraryOwner.setting] = $0 }
            )) {
                ForEach(members) { member in
                    Text(member.name).tag(Optional(member.id))
                }
            }
        }
    }

    private var ownerName: String {
        services.household.members.first { $0.id == services.photoLibraryOwnerID }?.name ?? "the owner"
    }

    private func binding(_ keyPath: WritableKeyPath<PhotoSourceSelection, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[PersonalSettings.photoSources][keyPath: keyPath] },
            set: { settings[PersonalSettings.photoSources][keyPath: keyPath] = $0 }
        )
    }

    private func albumBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings[PersonalSettings.photoSources].albumIDs.contains(id) },
            set: { isOn in
                settings[PersonalSettings.photoSources].albumIDs.removeAll { $0 == id }
                if isOn { settings[PersonalSettings.photoSources].albumIDs.append(id) }
            }
        )
    }
}
