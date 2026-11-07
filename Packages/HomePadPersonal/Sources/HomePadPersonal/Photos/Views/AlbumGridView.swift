import HomePadUI
import SwiftUI

/// The album list. The library comes first with Favorites and the photos
/// picked by hand, on wide covers. Shared albums (family can add to them from
/// anywhere) and the household's own albums follow on square covers. Columns
/// come from the width and the text size, and names wrap to three lines.
struct AlbumGridView: View {
    let albums: [PhotoAlbum]
    /// The recognized person's own iPhone, above the library, while it shows.
    var phone: PhoneAlbumsSection?
    let onOpen: (PhotoAlbum) -> Void

    /// The narrowest an album cover may get. Grows with the text size, so
    /// bigger names get fewer, wider columns.
    @ScaledMetric(relativeTo: .title3) private var minimumCover: CGFloat = 200

    var body: some View {
        let sections = PhotoAlbumRules.sections(albums)
        GeometryReader { proxy in
            let layout = Layout(width: proxy.size.width, height: proxy.size.height, minimumCover: minimumCover)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if let phone {
                        section(phone.title, systemImage: "iphone", albums: phone.library,
                                columns: layout.libraryColumns(count: phone.library.count),
                                coverAspect: layout.libraryAspect(count: phone.library.count), onOpen: phone.onOpen)
                        section(phone.albumsTitle, systemImage: "rectangle.stack.fill", albums: phone.albums,
                                columns: layout.albumColumns, coverAspect: 1, onOpen: phone.onOpen)
                    }
                    section("Library", systemImage: "photo.on.rectangle", albums: sections.library,
                            columns: layout.libraryColumns(count: sections.library.count),
                            coverAspect: layout.libraryAspect(count: sections.library.count))
                    section("Shared Albums", systemImage: "person.2.fill", albums: sections.shared,
                            columns: layout.albumColumns, coverAspect: 1)
                    section("Albums", systemImage: "rectangle.stack.fill", albums: sections.albums,
                            columns: layout.albumColumns, coverAspect: 1)
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func section(_ title: String, systemImage: String, albums: [PhotoAlbum], columns: Int, coverAspect: CGFloat,
                         onOpen: ((PhotoAlbum) -> Void)? = nil) -> some View {
        let onOpen = onOpen ?? self.onOpen
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title, systemImage: systemImage)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.l, alignment: .top), count: columns),
                          alignment: .leading, spacing: Theme.Spacing.l) {
                    ForEach(albums) { album in
                        Button { onOpen(album) } label: { card(album, coverAspect: coverAspect) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func card(_ album: PhotoAlbum, coverAspect: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Color.clear
                .aspectRatio(coverAspect, contentMode: .fit)
                .overlay { cover(album) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            Text(album.title)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Label(album.countText, systemImage: album.systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func cover(_ album: PhotoAlbum) -> some View {
        if let photo = album.keyPhoto {
            PhotoView(photo: photo, targetSize: PhotoGridMetrics.coverPixels)
        } else {
            Rectangle().fill(.primary.opacity(0.08))
                .overlay { Image(systemName: album.systemImage).font(.largeTitle).foregroundStyle(.secondary) }
        }
    }

    /// Column counts and cover shapes for the space on screen.
    struct Layout {
        let width: CGFloat
        let height: CGFloat
        let minimumCover: CGFloat

        /// Square album covers: as many columns as fit at `minimumCover`.
        var albumColumns: Int {
            max(1, Int((width + Theme.Spacing.l) / (minimumCover + Theme.Spacing.l)))
        }

        /// The library row: wider covers in at least two columns, so the
        /// library alone still reads as the main album and never fills the row.
        func libraryColumns(count: Int) -> Int {
            let fitting = max(1, Int((width + Theme.Spacing.l) / (minimumCover * 1.4 + Theme.Spacing.l)))
            return min(fitting, max(2, count))
        }

        /// 4:3 covers, made wider when taller covers would push the albums
        /// below off the screen.
        func libraryAspect(count: Int) -> CGFloat {
            let columns = CGFloat(libraryColumns(count: count))
            let coverWidth = (width - Theme.Spacing.l * (columns - 1)) / columns
            return max(4 / 3, coverWidth / max(height * 0.4, 1))
        }
    }
}
