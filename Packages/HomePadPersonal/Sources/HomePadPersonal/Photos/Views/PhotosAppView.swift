import HomePadCore
import HomePadUI
import PhotosUI
import SwiftUI

/// The Photos app: the library, favorites, shared albums and albums, a photo
/// grid per album, the full-screen viewer and the slideshow. Photos can also be
/// picked one by one with the system photo picker.
///
/// The viewer and the slideshow draw over the grid rather than in a cover, so
/// the grid shows through as one is swiped down, and closing finds it on the
/// same album, scrolled to the photo the viewer ended on.
///
/// It reopens on the album each person had open, scrolled where they left
/// the grid, or on the albums when that album is gone. The viewer and the
/// slideshow are not reopened.
///
/// What it shows follows `PhotoAccessPolicy`: the library's owner sees every
/// album, the system photo picker and Allow More Photos, another recognized
/// member sees the shared albums only, and a guest gets the recognition gate.
struct PhotosAppView: View {
    @Environment(PhotoLibraryService.self) private var photos
    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppState(PersonalAppState.photosAlbum) private var openAlbumID
    @AppState(PersonalAppState.photosGridTop) private var gridTop
    /// The open album's photos. Nil while they load.
    @State private var albumPhotos: [PhotoRef]?
    @State private var viewer: PhotoViewerRequest?
    /// The photo the viewer shows now.
    @State private var viewedPhoto: PhotoRef?
    @State private var thumbnails = ThumbnailFrames()
    /// A photo to open once the album has loaded (`-HomePadPhotosViewer`).
    @State private var pendingViewerIndex: Int?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var contentWidth: CGFloat = 0
    @State private var appliedDebugLaunch = false
    /// An album of the recognized person's phone, open over the albums.
    @State private var phoneAlbum: PhoneAlbum?

    var body: some View {
        ZStack {
            AppScreen(headerTitle, onBack: openAlbum == nil ? nil : { closeAlbum() }, backLabel: "Albums", accessory: { accessory }) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            }
            .accessibilityHidden(viewer != nil || openPhoneAlbum != nil)
            .opacity(openPhoneAlbum == nil ? 1 : 0)
            if let album = openPhoneAlbum, let library = phoneLibrary {
                PhoneAlbumScreen(album: album, deviceName: library.deviceName) { phoneAlbum = nil }
            }
            if let viewer {
                PhotoViewer(request: viewer, thumbnailFrame: { [thumbnails] in thumbnails.frame(of: $0) },
                            onShow: { viewedPhoto = $0 }, onClose: closeViewer)
                    .id(viewer.id)
                    .zIndex(1)
            }
        }
        .task(id: photos.isUsingDemoData) { photos.reload() }
        .task(id: AlbumLoad(albumID: openAlbum?.id, revision: photos.revision)) { await loadOpenAlbum() }
        .task(id: photos.revision) { await applyDebugLaunch() }
        .reportsScreenFocus(openAlbum, at: \.album)
        // Someone else at the screen never sees a photo opened for the last person.
        .onChange(of: access.viewerID) { closeViewer() }
        .onChange(of: pickerItems) {
            photos.setPickedPhotos(pickerItems.compactMap(\.itemIdentifier))
        }
    }

    // MARK: Content

    /// Which photos the person at the screen may see.
    private var access: PhotoAccessPolicy { services.photoAccess }

    /// The albums the person at the screen may see.
    private var albums: [PhotoAlbum] { photos.albums(for: access) }

    private var ownerName: String {
        services.household.members.first { $0.id == access.ownerID }?.name ?? "The iPad's owner"
    }

    @ViewBuilder
    private var content: some View {
        if let phone = phoneSection, openAlbum == nil,
           !photos.canShowPhotos || (photos.hasLoaded && PhotoAlbumRules.hasNoPhotos(albums)) {
            // The person's phone has photos even when this iPad shows none, or none they may see.
            AlbumGridView(albums: [], phone: phone) { _ in }
        } else if !photos.canShowPhotos, !access.allowsLibrary {
            EmptyStateView("Photos Is Not Set Up", message: "Once \(ownerName) allows HomePad to see photos, the Shared Albums show here.",
                           systemImage: "photo.on.rectangle.angled")
        } else if !photos.canShowPhotos {
            PermissionPrompt(feature: "Photos", systemImage: "photo.on.rectangle.angled",
                             reason: "Show your photo library, favorites and shared albums, so family far away can add photos to this HomePad. Nothing leaves this iPad.",
                             isDenied: photos.isDenied) { await photos.requestAccess() }
        } else if let album = openAlbum {
            albumDetail(album)
        } else if !photos.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if PhotoAlbumRules.hasNoPhotos(albums) {
            if !access.allowsLibrary {
                EmptyStateView("No Shared Albums Yet", message: "iCloud Shared Albums show here for everyone in the household. The rest of this iPad's photos show only to \(ownerName).",
                               systemImage: "person.2.crop.square.stack")
            } else if photos.isLimited {
                EmptyStateView("No Photos Allowed Yet", message: "HomePad can see only the photos you allow. Choose some to show here.",
                               systemImage: "photo.badge.checkmark", actionTitle: "Allow More Photos") { photos.chooseAllowedPhotos() }
            } else {
                EmptyStateView("No Photos Yet", message: "Photos saved on this iPad or in iCloud Photos show here, and so do iCloud Shared Albums.",
                               systemImage: "photo.stack")
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if photos.isLimited, access.allowsLibrary { limitedAccessNote }
                AlbumGridView(albums: albums, phone: phoneSection) { album in
                    withAnimation(Theme.Motion.standard) { openAlbumID = album.id }
                }
            }
        }
    }

    private func albumDetail(_ album: PhotoAlbum) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if !titleFitsHeader(album.title) {
                Text(album.title)
                    .font(.title.weight(.bold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(countText(album), systemImage: album.systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let albumPhotos {
                PhotoGridView(photos: albumPhotos, viewedPhoto: viewedPhoto, hidesViewedPhoto: viewer?.mode == .browse,
                              thumbnails: thumbnails, topPhotoID: topPhotoID(in: album)) { start in
                    viewer = PhotoViewerRequest(photos: albumPhotos, start: start, title: album.title, mode: .browse)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// With limited access the library holds only the photos the person allowed.
    private var limitedAccessNote: some View {
        let note = Label("HomePad can see only the photos you allowed.", systemImage: "photo.badge.checkmark")
            .font(.headline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        let button = GlassCapsuleButton("Allow More Photos", systemImage: "plus") { photos.chooseAllowedPhotos() }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.m) {
                note.fixedSize()
                Spacer(minLength: 0)
                button.fixedSize()
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                note
                button
            }
        }
    }

    /// The recognized person's phone library, while it may show (`PhoneLibraryVisibility`).
    private var phoneLibrary: PhoneLibrary? {
        PhoneLibraryVisibility.shown(services.phonePhotos.library, unlockedMember: services.household.unlockedMember?.id,
                                     access: access)
    }

    private var phoneSection: PhoneAlbumsSection? {
        phoneLibrary.map { PhoneLibraryVisibility.section($0) { phoneAlbum = $0 } }
    }

    /// The open phone album, while the phone's library still shows and holds it.
    private var openPhoneAlbum: PhoneAlbum? {
        guard let phoneAlbum, let library = phoneLibrary else { return nil }
        return library.albums.first { $0.id == phoneAlbum.id }
    }

    /// The open album, while it is still in the library.
    private var openAlbum: PhotoAlbum? {
        guard let openAlbumID else { return nil }
        return albums.first { $0.id == openAlbumID }
    }

    /// The photo at the top of an album's grid, saved once scrolling stops.
    private func topPhotoID(in album: PhotoAlbum) -> Binding<String?> {
        Binding(
            get: { gridTop?.albumID == album.id ? gridTop?.photoID : nil },
            set: { gridTop = $0.map { PhotoGridPosition(albumID: album.id, photoID: $0) } }
        )
    }

    // MARK: Header

    /// The album name, or what kind of album it is when the name is too long
    /// for the header. The full name then heads the album's content instead.
    private var headerTitle: String {
        guard let album = openAlbum else { return "Photos" }
        if titleFitsHeader(album.title) { return album.title }
        switch album.kind {
        case .shared: return "Shared Album"
        case .picked: return "Selected Photos"
        default: return "Album"
        }
    }

    private func titleFitsHeader(_ title: String) -> Bool {
        contentWidth == 0 || Self.titleFitsHeader(title, width: contentWidth, typeSize: typeSize)
    }

    /// True when a title at the screen title style fits the header's leading
    /// side beside the back button, without shrinking or cutting off.
    static func titleFitsHeader(_ title: String, width: CGFloat, typeSize: DynamicTypeSize) -> Bool {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let pointSize = UIFont.preferredFont(forTextStyle: .largeTitle, compatibleWith: traits).pointSize
        let font = UIFont.systemFont(ofSize: pointSize, weight: .bold)
        return (title as NSString).size(withAttributes: [.font: font]).width <= HeaderMetrics.titleRoom(rowWidth: width, hasBackButton: true)
    }

    /// Choose Photos gives way first, Play Slideshow is the one prominent action.
    @ViewBuilder
    private var accessory: some View {
        if openAlbum == nil, photos.canShowPhotos, !photos.isUsingDemoData, access.allowsLibrary {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 200, selectionBehavior: .ordered, matching: .images, photoLibrary: .shared()) {
                Label("Choose Photos", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.glassIcon())
            .accessibilityLabel("Choose Photos")
            .headerItem()
            .toolbarItemPriority(.low)
        }
        if showsPlay {
            GlassIconButton("play.fill", label: "Play Slideshow", isProminent: true) {
                Task { await playSlideshow() }
            }
            .disabled(!canPlay)
        }
    }

    /// An album shows Play while its photos load, dimmed, and loses it only
    /// when it turns out empty. Leaving and coming back as the photos loaded
    /// made the header jump, and on the M4 iPad the button came back as a
    /// red circle without its symbol.
    private var showsPlay: Bool {
        guard photos.canShowPhotos else { return false }
        if openAlbum != nil { return albumPhotos?.isEmpty != true }
        return photos.hasLoaded && !PhotoAlbumRules.hasNoPhotos(albums)
    }

    /// The open album's photos and videos once loaded, else the album's own counts.
    private func countText(_ album: PhotoAlbum) -> String {
        guard let albumPhotos else { return album.countText }
        let videos = albumPhotos.count { photos.videoDuration(for: $0) != nil }
        return PhotoAlbum.countText(albumPhotos.count - videos, videos: videos)
    }

    private var canPlay: Bool {
        guard photos.canShowPhotos else { return false }
        if openAlbum != nil { return albumPhotos?.isEmpty == false }
        return photos.hasLoaded && !PhotoAlbumRules.hasNoPhotos(albums)
    }

    // MARK: Actions

    private func closeAlbum() {
        withAnimation(Theme.Motion.standard) { openAlbumID = nil }
    }

    private func loadOpenAlbum() async {
        guard let album = openAlbum else {
            albumPhotos = nil
            return
        }
        // Photos already on screen stay while the library refreshes.
        let loaded = await photos.photos(in: album)
        guard !Task.isCancelled else { return }
        albumPhotos = loaded
        if let index = pendingViewerIndex, loaded.indices.contains(index) {
            pendingViewerIndex = nil
            viewer = PhotoViewerRequest(photos: loaded, start: loaded[index], title: album.title, mode: .browse)
        }
    }

    /// Removes the viewer at once: it has already shrunk into its thumbnail
    /// or slid away, and the thumbnail shows again in the same frame.
    private func closeViewer() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            viewer = nil
            viewedPhoto = nil
        }
    }

    private func playSlideshow() async {
        let list: [PhotoRef]
        if let albumPhotos, openAlbum != nil {
            list = albumPhotos
        } else if let openAlbum {
            list = await photos.photos(in: openAlbum)
        } else {
            list = await photos.slideshowPhotos(access: access)
        }
        if !list.isEmpty { viewer = PhotoViewerRequest(photos: list, start: nil, title: openAlbum?.title ?? "Photos", mode: .slideshow) }
    }

    /// Opens an album or the slideshow from the debug launch arguments, once
    /// the albums have loaded. They win over the album Photos was left on.
    private func applyDebugLaunch() async {
        guard !appliedDebugLaunch, photos.hasLoaded else { return }
        appliedDebugLaunch = true
        if let wanted = PersonalDebugLaunch.photosAlbum,
           let album = albums.first(where: { $0.title == wanted || $0.kind.rawValue == wanted }) {
            openAlbumID = album.id
            pendingViewerIndex = PersonalDebugLaunch.photosViewerIndex
        }
        if PersonalDebugLaunch.startsPhotosSlideshow { await playSlideshow() }
    }

    private struct AlbumLoad: Hashable {
        var albumID: String?
        var revision: Int
    }
}
