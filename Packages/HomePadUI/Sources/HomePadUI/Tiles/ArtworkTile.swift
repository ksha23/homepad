import HomePadCore
import SwiftUI

/// Square artwork with a title (`Font.tileTitle`) and subtitle
/// (`Font.tileDetail`) underneath, for browse rows and grids: albums,
/// stations, playlists, recipes. The artwork is any view, so
/// MusicKit artwork, a remote image or a symbol all fit. `isActive` marks
/// the item that is playing now.
///
///     ShelfRow("Recently Played") {
///         ForEach(items) { item in
///             ArtworkTile(title: item.title, subtitle: item.artist, action: { play(item) }) {
///                 ArtworkView(artwork: item.artwork)
///             }
///         }
///     }
public struct ArtworkTile<Artwork: View>: View {
    private let title: String
    private let subtitle: String?
    private let isActive: Bool
    private let width: CGFloat
    private let action: () -> Void
    private let artwork: Artwork
    @Environment(\.allowsContinuousMotion) private var allowsMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - title: First line under the artwork.
    ///   - subtitle: Optional second line.
    ///   - isActive: Shows a moving waveform badge on the artwork.
    ///   - width: Edge length of the artwork, also the tile width.
    ///   - action: Called on tap.
    ///   - artwork: The artwork, drawn square. Clip it yourself if it needs rounded corners.
    public init(
        title: String, subtitle: String? = nil, isActive: Bool = false, width: CGFloat = 180,
        action: @escaping () -> Void, @ViewBuilder artwork: () -> Artwork
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isActive = isActive
        self.width = width
        self.action = action
        self.artwork = artwork()
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                artwork
                    .frame(width: width, height: width)
                    .overlay(alignment: .bottomTrailing) {
                        if isActive {
                            Image(systemName: "waveform")
                                .font(.headline)
                                .padding(Theme.Spacing.s)
                                .glassEffect(.regular, in: .circle)
                                .padding(Theme.Spacing.s)
                                // An endless symbol effect redraws every frame, so it
                                // holds still while the display is dimmed or asleep.
                                .symbolEffect(.variableColor.iterative, isActive: allowsMotion && !reduceMotion)
                        }
                    }
                // A long title shrinks to Headline before it is cut off.
                Text(title)
                    .font(.tileTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let subtitle {
                    Text(subtitle)
                        .font(.tileDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
