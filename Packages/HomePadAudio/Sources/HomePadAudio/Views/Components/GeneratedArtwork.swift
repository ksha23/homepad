import HomePadUI
import SwiftUI

/// Cover art for items without any: a calm two-color gradient picked from the
/// curated palette by the item's name, with the name set in big type, like Apple
/// Music's own playlist covers. The same name always gets the same colors.
/// Candidate for HomePadUI.
struct GeneratedArtwork: View {
    /// What the cover shows over the gradient.
    enum Style {
        /// The name in big type with the symbol, like a playlist cover.
        case titled
        /// Centered initials, for round artist pictures.
        case monogram
        /// Only the symbol, for small thumbnails.
        case symbol
    }

    let seed: String
    var systemImage: String = "music.note"
    var style: Style = .titled

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let colors = Self.colors(for: seed)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: side * 0.9, height: side * 0.9)
                    .position(x: proxy.size.width * 0.9, y: proxy.size.height * 0.95)
                if style == .monogram {
                    Text(Self.initials(of: seed))
                        .font(.system(size: side * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if style == .titled && side > 90 {
                    // Wide tiles (moods) size the title from their height, square covers from their side.
                    let titleSize = proxy.size.width > proxy.size.height * 1.3 ? min(proxy.size.height * 0.2, 30) : side * 0.12
                    VStack(alignment: .leading, spacing: side * 0.03) {
                        Text(seed)
                            .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 0)
                        Image(systemName: systemImage)
                            .font(.system(size: side * 0.13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(side * 0.09)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: side * 0.36, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// "Neon Avenue" becomes "NA", "Lumen" becomes "L".
    static func initials(of name: String) -> String {
        String(name.split(separator: " ").filter { $0.lowercased() != "the" }.prefix(2).compactMap(\.first)).uppercased()
    }

    /// Two neighboring palette colors chosen by a stable hash of the name.
    static func colors(for seed: String) -> (Color, Color) {
        let swatches = Theme.Palette.swatches
        let hash = seed.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0x7fffffff }
        let first = swatches[hash % swatches.count]
        let second = swatches[(hash / swatches.count + 1 + hash % swatches.count) % swatches.count]
        return (first.color, second.color.opacity(first == second ? 0.6 : 1))
    }
}
