import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.analog`: a calm analog clock with numerals pressed into a soft
/// surface, like HomeView's embossed white clock. Its large numerals follow
/// the face's rounded edge, so a landscape screen's sides are not left
/// empty. The Precision style puts smaller numerals on a ticked round dial.
/// Up close the second hand and the date fade in.
///
/// While the face has widgets, the embossed numerals keep inside the dial's
/// region, whose cells no widget may cover (`FaceContentRegion`).
struct AnalogFace: View {
    static let style = FaceOption.style([
        FaceChoice("embossed", "Embossed", systemImage: "clock"),
        FaceChoice("precision", "Precision", systemImage: "clock.badge"),
    ])
    static let color = FaceOption.color([.porcelain, .sand, .rose, .sage, .ocean, .lavender, .graphite], default: .porcelain)

    static let definition = FaceDefinition(
        id: "faces.analog", title: "Analog", summary: "A quiet clock with numerals pressed into the surface",
        systemImage: "clock", sortOrder: 40, options: [style, color],
        widgets: .around(.centered(width: 0.84, height: 0.84), landscapeFill: .trailingColumns)
    ) { AnalogFace() }

    /// The embossed numerals' font size, as a share of the shorter side of
    /// the room they follow: the 12 stands about a tenth of it tall.
    static let edgeNumeralShare: CGFloat = 0.15

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity
    @Environment(\.faceInsets) private var faceInsets
    @Environment(\.faceKeepClear) private var keepClear
    @Environment(\.faceHasWidgets) private var hasWidgets

    var body: some View {
        let palette = FacePalette.resolve(configuration.colors(Self.color), condition: condition)
        let isNear = proximity >= .mid
        let isPrecision = configuration.value(Self.style) == "precision"
        FaceTimeline(isNear ? .second : .minute) { date in
            GeometryReader { proxy in
                // Clear of the Now Playing pill while it shows: smaller, still centered.
                let area = proxy.size.leaving(keepClear.balancedVertically)
                let side = min(area.width, area.height) * 0.92
                ZStack {
                    Rectangle().fill(palette.background).ignoresSafeArea()
                    if !isPrecision {
                        let bounds = numeralBounds(size: proxy.size)
                        edgeNumerals(palette: palette, bounds: bounds)
                            .frame(width: bounds.width, height: bounds.height)
                            .position(x: bounds.midX, y: bounds.midY)
                    }
                    ZStack {
                        if isPrecision {
                            DialTicks(color: palette.secondary)
                            dialNumerals(palette: palette)
                        }
                        if isNear {
                            DateBadge(date: date, palette: palette)
                                .font(.display(side * 0.035, weight: .semibold))
                                .position(x: side * 0.73, y: side * 0.5)
                                .transition(.proximityDetail)
                        }
                        ClockHands(angles: ClockMath.angles(for: date), style: .standard(
                            ink: palette.isNight ? palette.accent : palette.ink, accent: palette.accent, showsSecond: isNear))
                    }
                    .frame(width: side, height: side)
                    .centered(in: proxy.size, clearOf: keepClear.balancedVertically)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .faceBackdrop(tone: palette.tone) { palette.background.ignoresSafeArea() }
    }

    /// The room the embossed numerals follow the edge of: inside the face
    /// insets, as far from the bottom as the Now Playing pill takes from the
    /// top so the numerals stay centered on the dial, and inside the dial's
    /// region while the face has widgets.
    private func numeralBounds(size: CGSize) -> CGRect {
        let region = hasWidgets
            ? Self.definition.widgets.region.rects(configuration: configuration, size: size, insets: faceInsets).first
            : nil
        return Self.numeralBounds(size: size, insets: faceInsets, keepClear: keepClear, region: region)
    }

    /// See `numeralBounds(size:)`.
    static func numeralBounds(size: CGSize, insets: EdgeInsets, keepClear: EdgeInsets, region: CGRect?) -> CGRect {
        let balance = keepClear.balancedVertically.bottom - keepClear.bottom
        let content = CGRect(x: insets.leading, y: insets.top,
                             width: max(size.width - insets.leading - insets.trailing, 0),
                             height: max(size.height - insets.top - insets.bottom - balance, 0))
        guard let region else { return content }
        let inside = content.intersection(region)
        return inside.isNull ? .zero : inside
    }

    /// Large numerals pressed into the surface, along the rounded edge of `bounds`.
    private func edgeNumerals(palette: FacePalette, bounds: CGRect) -> some View {
        let size = min(bounds.width, bounds.height) * Self.edgeNumeralShare
        // Inset by about half a two-digit numeral's width, so 10 and 11 keep inside too.
        return DialNumerals(path: .roundedRect(inset: size * 0.6, cornerRadius: min(bounds.width, bounds.height) * 0.2)) { value, _ in
            numeral(value, palette: palette, font: .display(size, weight: .regular), depth: size * 0.025)
        }
    }

    /// The Precision style's numerals, around the ticked dial.
    private func dialNumerals(palette: FacePalette) -> some View {
        DialNumerals(radiusFraction: 0.74) { value, radius in
            numeral(value, palette: palette, font: .display(radius * 0.15, weight: .medium), depth: radius * 0.008)
        }
    }

    @ViewBuilder
    private func numeral(_ numeral: Int, palette: FacePalette, font: Font, depth: CGFloat) -> some View {
        if palette.isNight || !palette.isLight {
            Text("\(numeral)").font(font).foregroundStyle(palette.secondary)
        } else {
            // Pressed into the surface, in the text color when one is chosen.
            EmbossedText(text: "\(numeral)", font: font, surface: palette.hasChosenText ? palette.ink : palette.top,
                         depth: depth)
        }
    }
}
