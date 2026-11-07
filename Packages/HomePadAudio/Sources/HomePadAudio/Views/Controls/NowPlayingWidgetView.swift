import HomePadCore
import HomePadUI
import SwiftUI

/// The Now Playing widget for the Home Screen and faces. Every size has play
/// or pause and the volume, and medium and large add back, forward and AirPlay.
/// The volume stands at the trailing edge as tall as the tile, like the volume
/// beside Control Center's media tile.
///
/// The controls come first. Each size lays itself out from the space its tile
/// gives it: larger text drops title lines and the artwork shrinks or goes
/// before the controls get smaller than `Theme.Size.tapTarget`, and they never
/// get smaller than `Theme.Size.minTapTarget`.
///
/// The volume is the level Now Playing sets (`NowPlayingVolumeTarget`), drawn
/// as a `BigSlider`. Its drag starts as the finger lands, so it keeps the touch
/// from the face and Home Screen pages, the tap that opens Music and the holds
/// that edit the Home Screen or choose a face. Being upright, it also moves
/// along the other axis from the pages.
struct NowPlayingWidgetView: View {
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services
    let size: WidgetSize

    var body: some View {
        GlassTile {
            switch size {
            case .small: small
            case .medium: medium
            // Tall is not offered (`WidgetSize.standard`). The large layout grows its artwork into any height.
            case .large, .tall: large
            }
        }
    }

    // MARK: Small

    /// The title over play or pause, beside the volume. A tall cell, such as a
    /// face's on a 13-inch iPad, shows the artwork over the title.
    private var small: some View {
        HStack(spacing: Theme.Spacing.controlGap) {
            ViewThatFits(in: .vertical) {
                smallColumn(controls: Theme.Size.tapTarget, titleLines: 2, minArtwork: Theme.Size.tapTarget)
                smallColumn(controls: Theme.Size.tapTarget, titleLines: 3)
                smallColumn(controls: Theme.Size.tapTarget, titleLines: 2)
                smallColumn(controls: Theme.Size.tapTarget, titleLines: 1)
                smallColumn(controls: Theme.Size.toolbarItem, titleLines: 1)
                smallColumn(controls: Theme.Size.minTapTarget, titleLines: 1)
            }
            // Narrower than in the larger sizes, so the title keeps room for a few words a line.
            volume(width: Theme.Size.minTapTarget)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }

    private func smallColumn(controls height: CGFloat, titleLines: Int, minArtwork: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let minArtwork {
                flexibleArtwork(minSide: minArtwork, alignment: .bottomLeading)
            }
            // Without a cover the title's frame takes the room left and keeps the controls
            // at the bottom. A Spacer would count the stack's gap twice in the height
            // ViewThatFits measures, and cut a two line title that fits to one.
            Text(title).font(.headline).lineLimit(titleLines)
                .frame(maxHeight: minArtwork == nil ? .infinity : nil, alignment: .topLeading)
            TransportControls(height: height, showsSkip: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Medium

    /// The artwork beside the title and artist, over the transport and AirPlay,
    /// with the volume at the trailing edge.
    private var medium: some View {
        ViewThatFits(in: .vertical) {
            mediumLayout(controls: Theme.Size.tapTarget, titleLines: 2, showsArtist: true, artwork: Theme.Size.tapTarget)
            mediumLayout(controls: Theme.Size.tapTarget, titleLines: 1, showsArtist: true, artwork: Theme.Size.minTapTarget)
            mediumLayout(controls: Theme.Size.tapTarget, titleLines: 1, showsArtist: false, artwork: Theme.Size.minTapTarget)
            mediumLayout(controls: Theme.Size.tapTarget, titleLines: 1, showsArtist: false, artwork: nil)
            mediumLayout(controls: Theme.Size.toolbarItem, titleLines: 1, showsArtist: false, artwork: nil)
            mediumLayout(controls: Theme.Size.minTapTarget, titleLines: 1, showsArtist: false, artwork: nil)
        }
    }

    private func mediumLayout(controls height: CGFloat, titleLines: Int, showsArtist: Bool, artwork side: CGFloat?) -> some View {
        HStack(spacing: Theme.Spacing.controlGap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    if let side {
                        artwork.frame(width: side, height: side)
                    }
                    details(titleFont: .headline, titleLines: titleLines, showsArtist: showsArtist)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
                // Takes the room left, so the transport sits at the bottom with the gap counted once.
                .frame(maxHeight: .infinity, alignment: .top)
                transportRow(height: height)
            }
            volume(width: height)
        }
    }

    // MARK: Large

    /// The artwork over the title and artist, then the transport and AirPlay,
    /// with the volume at the trailing edge. The artwork takes whatever height
    /// the rest leaves.
    private var large: some View {
        ViewThatFits(in: .vertical) {
            largeLayout(controls: Theme.Size.tapTarget, titleLines: 2, showsArtist: true, minArtwork: Theme.Size.tapTarget)
            largeLayout(controls: Theme.Size.tapTarget, titleLines: 1, showsArtist: true, minArtwork: Theme.Size.tapTarget)
            largeLayout(controls: Theme.Size.tapTarget, titleLines: 2, showsArtist: true, minArtwork: nil)
            largeLayout(controls: Theme.Size.toolbarItem, titleLines: 1, showsArtist: true, minArtwork: nil)
            largeLayout(controls: Theme.Size.minTapTarget, titleLines: 1, showsArtist: false, minArtwork: nil)
        }
    }

    private func largeLayout(controls height: CGFloat, titleLines: Int, showsArtist: Bool, minArtwork: CGFloat?) -> some View {
        HStack(spacing: Theme.Spacing.controlGap) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if let minArtwork {
                        flexibleArtwork(minSide: minArtwork, alignment: .topLeading)
                    }
                    details(titleFont: .tileTitle, titleLines: titleLines, showsArtist: showsArtist)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
                // Takes the room left (the cover grows into it), so the transport sits at the bottom.
                .frame(maxHeight: .infinity, alignment: .top)
                transportRow(height: height)
            }
            volume(width: height)
        }
    }

    // MARK: Parts

    private func details(titleFont: Font, titleLines: Int, showsArtist: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(titleFont).lineLimit(titleLines)
            if showsArtist {
                Text(subtitle).font(.tileDetail).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Back, play or pause and forward, with AirPlay at the far end. Not where the volume
    /// is the AirPlay menu itself, which drew a second AirPlay button.
    private func transportRow(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            TransportControls(height: height)
            Spacer(minLength: Theme.Spacing.controlGap)
            if media.volumeTarget != .airPlayMenu {
                AirPlayButton(size: Theme.Size.minTapTarget)
            }
        }
    }

    /// The volume Now Playing sets, standing at the trailing edge as tall as the tile's content.
    private func volume(width: CGFloat) -> some View {
        NowPlayingVolumeSlider(style: .bar(.vertical))
            .frame(width: width)
            .frame(maxHeight: .infinity)
    }

    /// A cover that is at least `minSide` and grows into the height the rest
    /// leaves. Its ideal height is the smallest cover, so `ViewThatFits`
    /// measures each layout at that size. Laid out, it takes the rest.
    private func flexibleArtwork(minSide side: CGFloat, alignment: Alignment) -> some View {
        artwork.frame(minWidth: side, idealWidth: side, maxWidth: .infinity,
                      minHeight: side, idealHeight: side, maxHeight: .infinity, alignment: alignment)
    }

    private var title: String { media.nowPlaying?.title ?? "Not Playing" }

    private var subtitle: String { media.nowPlaying?.artist ?? media.musicOutputName ?? "" }

    @ViewBuilder
    private var artwork: some View {
        if let nowPlaying = media.nowPlaying {
            NowPlayingArtwork(nowPlaying: nowPlaying, cornerRadius: Theme.Radius.tileControl)
        } else {
            ArtworkView(cornerRadius: Theme.Radius.tileControl)
        }
    }

    private func open() {
        services.events.post(.openApp(id: AudioModule.nowPlayingAppID))
    }
}
