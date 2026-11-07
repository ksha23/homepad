import HomePadCore
import HomePadUI
import SwiftUI

/// An album, playlist or artist page, from any source: the artwork beside the
/// title with Play, Shuffle and a More menu (Play Next, Play Later, Add to
/// Library, the artist), then the track list, then shelves such as an artist's albums.
struct MusicDetailView: View {
    let page: MusicPage
    @Environment(AudioMediaService.self) private var media
    @Environment(\.musicContentWidth) private var width
    @State private var detail: MusicDetail?
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let detail {
                    MusicDetailHeader(detail: detail, isCompact: width < 720)
                    trackList(detail)
                    ForEach(detail.shelves) { MusicShelf(shelf: $0) }
                } else if let failure {
                    EmptyStateView("Couldn't Open \(page.title)", message: failure, systemImage: "exclamationmark.triangle",
                                   actionTitle: "Try Again") {
                        self.failure = nil
                        attempt += 1
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    loading
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .task(id: attempt) {
            do {
                detail = try await media.loadDetail(page)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func trackList(_ detail: MusicDetail) -> some View {
        if !detail.tracks.isEmpty {
            // The song that plays now shows a waveform, if it is on this page.
            let playing = media.nowPlaying?.isPlaying == true ? media.nowPlaying?.title : nil
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let title = detail.tracksTitle { SectionHeader(title) }
                ForEach(detail.tracks) { track in
                    row(track, isPlaying: track.item.title == playing)
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private func row(_ track: MusicDetail.Track, isPlaying: Bool) -> some View {
        var item = track.item
        item.isActive = isPlaying
        return SongRow(item: item, trailing: track.durationText, number: track.number)
    }

    /// The header's size and a few rows, so nothing moves when the page arrives.
    private var loading: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.l) {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(.primary.opacity(0.08))
                    .frame(width: MusicDetailHeader.artworkSide, height: MusicDetailHeader.artworkSide)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(page.title).font(.glanceTitle)
                    Text("Loading").font(.glanceSubtitle).foregroundStyle(.secondary)
                }
                .redacted(reason: .placeholder)
            }
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}

/// The top of a page: artwork, kind, title, subtitle, details and the actions.
struct MusicDetailHeader: View {
    let detail: MusicDetail
    var isCompact = false

    /// Large enough to read from a step back, small enough to leave the track list in view.
    static let artworkSide: CGFloat = 240

    var body: some View {
        let layout = isCompact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.l))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: Theme.Spacing.xl))
        layout {
            Button(action: detail.header.action) {
                detail.header.artworkView(cornerRadius: detail.header.isRound ? Theme.Radius.pill : Theme.Radius.tile)
                    .frame(width: Self.artworkSide, height: Self.artworkSide)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(detail.title)")
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(detail.kind.title.uppercased())
                    .font(.headline)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(detail.title)
                    .font(.glanceTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let subtitle = detail.subtitle {
                    Text(subtitle).font(.glanceSubtitle).foregroundStyle(.tint).lineLimit(1)
                }
                if let line = detail.detail {
                    Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }
                actions
                    .padding(.top, Theme.Spacing.s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let play = detail.actions.play {
                GlassCapsuleButton("Play", systemImage: "play.fill", isProminent: true, tint: .pink, action: play)
            }
            if let shuffle = detail.actions.shuffle {
                GlassCapsuleButton("Shuffle", systemImage: "shuffle", action: shuffle)
            }
            let more = MusicItemMenu(playNext: detail.actions.playNext, playLater: detail.actions.playLater,
                                     open: detail.actions.open, openTitle: detail.actions.openTitle,
                                     openSystemImage: detail.actions.openSystemImage, addToLibrary: detail.actions.addToLibrary)
            if !more.isEmpty {
                Menu {
                    MusicItemMenuContent(menu: more)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .buttonStyle(.glassIcon(size: Theme.Size.tapTarget))
            }
        }
    }
}

extension AudioMediaService {
    /// Loads a page from its source.
    func loadDetail(_ page: MusicPage) async throws -> MusicDetail {
        switch page {
        case .appleMusicAlbum, .appleMusicPlaylist, .appleMusicArtist:
            guard let detail = try await AppleMusicPages.detail(page, self) else { throw AudioError.nothingFound(page.title) }
            return detail
        case .demo(let item):
            return DemoMusicPages.detail(item, self)
        case .spotify(let item):
            return try await SpotifyPages.detail(item, self)
        case .memberPlaylist(let item):
            return try await MemberMusicTiles.playlistDetail(item, self)
        }
    }
}
