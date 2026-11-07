import HomePadCore
import HomePadUI
import PhotosUI
import SwiftUI

/// The "Photos" page of the Photos face editor: a row of source cards
/// (featured photos, the whole library, favorites, portraits, an album with
/// iCloud Shared Albums included, photos picked with the system photo picker,
/// or one photo that stays put), and under it one line about the chosen source
/// with its controls. Everything fits under the preview without scrolling.
///
/// Choosing albums and photos browses the iPad's library, so it follows
/// `PhotoAccessPolicy`: the library's owner chooses from everything, another
/// recognized member from the shared albums. The face itself shows what was
/// chosen to whoever is in the room, like a picture frame.
struct PhotoSourcePage: View {
    static let albumIDKey = "albumID"
    static let albumTitleKey = "albumTitle"
    static let pickedKey = "photos"
    /// The one photo a `.single` face shows.
    static let singleKey = "photo"

    /// Wide enough for every source's title, narrow enough that all seven fit
    /// in a row across an 11-inch iPad in landscape.
    private static let cardWidth: CGFloat = 124

    @Binding var configuration: FaceConfiguration
    @Environment(AppServices.self) private var services
    @State private var access = PhotoLibrarySource.access
    @State private var albums: [PhotoAlbum] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var singleItem: PhotosPickerItem?
    @State private var isFraming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            OptionCarousel(items: PhotoSourceKind.allCases, selection: sourceSelection, cardWidth: Self.cardWidth) { kind, isSelected in
                OptionCard(title: kind.title, isSelected: isSelected) {
                    Image(systemName: kind.systemImage).font(.largeTitle)
                }
            }
            .frame(height: OptionCard<EmptyView>.defaultIconSize.height + EditorMetrics.cardTitleHeight + Theme.Spacing.m * 3)
            HStack(spacing: Theme.Spacing.m) {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actions
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .task(id: access) {
            if access == .allowed || access == .limited { albums = await PhotoLibrarySource.albums() }
        }
        .onChange(of: pickerItems) { _, items in
            configuration.items[Self.pickedKey] = items.compactMap(\.itemIdentifier)
        }
        .onChange(of: singleItem) { _, item in
            guard let id = item?.itemIdentifier else { return }
            configuration.values[Self.singleKey] = id
            // A new photo starts unframed, filling the screen.
            PhotoFraming.clear(from: &configuration.values)
        }
        .fullScreenCover(isPresented: $isFraming) {
            PhotoFramingView(configuration: $configuration)
                .coverHomeBar()
        }
    }

    private var selected: PhotoSourceKind {
        PhotoSourceKind(rawValue: configuration.value(PhotosFace.source)) ?? .featured
    }

    private var sourceSelection: Binding<String?> {
        Binding(get: { selected.id }, set: { id in
            if let id { configuration.values[PhotosFace.source.id] = id }
        })
    }

    private var hasAccess: Bool { access == .allowed || access == .limited }

    // MARK: Details

    private var description: String {
        switch access {
        case .notAsked: return "Until you allow access, the face shows sample pictures."
        case .denied: return "Photos access is off. Turn it on in Settings, Privacy and Security, Photos."
        case .allowed, .limited: break
        }
        switch selected {
        case .featured: return "Portraits and favorites from the last two years, or your recent photos."
        case .library: return "The newest photos in your whole library, without screenshots."
        case .favorites: return "Photos you marked with a heart."
        case .portraits: return "Photos taken in Portrait mode. The time tucks in behind the people best in these."
        case .album: return "Choose a Shared Album so family and friends can add photos to this frame from anywhere."
        case .picked where !mayBrowseLibrary, .single where !mayBrowseLibrary:
            return "Photos from this iPad's library can be chosen while its owner is recognized."
        case .picked: return "Only the photos you choose."
        case .single: return "One photo you choose. It stays on the face and never changes or moves."
        }
    }

    @ViewBuilder
    private var actions: some View {
        if access == .notAsked {
            GlassCapsuleButton("Allow Photos", systemImage: "photo", isProminent: true) {
                Task {
                    _ = await PhotoLibrarySource.requestAccess()
                    access = PhotoLibrarySource.access
                }
            }
        } else if hasAccess {
            switch selected {
            case .album: albumMenu
            case .picked where mayBrowseLibrary: pickedButton
            case .single where mayBrowseLibrary: singleButtons
            case .picked, .single, .featured, .library, .favorites, .portraits: EmptyView()
            }
        }
    }

    /// The library's owner is recognized, so its own albums and the system photo picker may show.
    private var mayBrowseLibrary: Bool { services.photoAccess.allowsLibrary }

    /// The albums the person editing may choose from: every album for the
    /// library's owner, the shared albums for anyone else.
    private var choosableAlbums: [PhotoAlbum] {
        let access = services.photoAccess
        return albums.filter { access.allows($0.isShared ? .sharedAlbums : .library) }
    }

    private var albumMenu: some View {
        Menu {
            if choosableAlbums.isEmpty {
                Text("No albums with photos")
            }
            ForEach(choosableAlbums) { album in
                Button {
                    configuration.values[Self.albumIDKey] = album.id
                    configuration.values[Self.albumTitleKey] = album.title
                } label: {
                    if configuration.values[Self.albumIDKey] == album.id {
                        Label("\(album.title), \(album.count)", systemImage: "checkmark")
                    } else {
                        Text("\(album.title), \(album.count)")
                    }
                }
            }
        } label: {
            Label(configuration.values[Self.albumTitleKey] ?? "Choose Album", systemImage: "rectangle.stack")
        }
        .buttonStyle(.glassCapsule())
    }

    private var pickedButton: some View {
        let count = configuration.items[Self.pickedKey]?.count ?? 0
        return PhotosPicker(selection: $pickerItems, maxSelectionCount: 100, matching: .images, photoLibrary: .shared()) {
            Label(count == 0 ? "Choose Photos" : count == 1 ? "1 Photo" : "\(count) Photos", systemImage: "photo.badge.plus")
        }
        .buttonStyle(.glassCapsule())
    }

    private var singleButtons: some View {
        let hasPhoto = configuration.values[Self.singleKey] != nil
        return HStack(spacing: Theme.Spacing.s) {
            PhotosPicker(selection: $singleItem, matching: .images, photoLibrary: .shared()) {
                Label(hasPhoto ? "Change Photo" : "Choose Photo", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.glassCapsule())
            if hasPhoto {
                GlassCapsuleButton("Frame Photo", systemImage: "crop", isProminent: true) { isFraming = true }
            }
        }
    }
}
