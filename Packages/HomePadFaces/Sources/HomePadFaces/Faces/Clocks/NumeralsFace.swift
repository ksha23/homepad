import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.numerals`: four huge overlapping numerals (12, 3, 6, 9) under
/// bright hands, readable from across any room. Up close the second hand and
/// the date fade in.
struct NumeralsFace: View {
    static let style = FaceOption.style([
        FaceChoice("light", "Light", systemImage: "textformat.size.smaller"),
        FaceChoice("heavy", "Heavy", systemImage: "textformat.size.larger"),
    ])
    static let color = FaceOption.color([.green, .coral, .ocean, .lavender, .sand, .midnight, .graphite], default: .green)
    /// What widgets keep clear of: the four numerals and the hands, and the
    /// date in the bottom leading corner up close.
    static let region = FaceContentRegion.union([
        .centered(width: 0.86, height: 0.88),
        FaceContentRegion { _, size, insets in
            let font = min(size.width, size.height) * dateShare
            return [CGRect(x: insets.leading, y: size.height - insets.bottom - font * 1.3,
                           width: font * 4.5, height: font * 1.3)]
        },
    ])
    /// The date's font size, as a share of the face's shorter side.
    static let dateShare: CGFloat = 0.04

    static let definition = FaceDefinition(
        id: "faces.numerals", title: "Numerals", summary: "Giant 12, 3, 6 and 9 with bold hands",
        systemImage: "clock.circle", sortOrder: 41, options: [style, color],
        widgets: .around(region, landscapeFill: .trailingColumns)
    ) { NumeralsFace() }

    @Environment(\.faceInsets) private var faceInsets

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity
    @Environment(\.faceKeepClear) private var keepClear

    var body: some View {
        let palette = FacePalette.resolve(configuration.colors(Self.color), condition: condition)
        let weight: Font.Weight = configuration.value(Self.style) == "heavy" ? .semibold : .light
        let isNear = proximity >= .mid
        FaceTimeline(isNear ? .second : .minute) { date in
            GeometryReader { proxy in
                // Clear of the Now Playing pill while it shows: smaller, still centered.
                let area = proxy.size.leaving(keepClear.balancedVertically)
                let side = min(area.width, area.height)
                ZStack {
                    Rectangle().fill(palette.background).ignoresSafeArea()
                    ZStack {
                        numerals(side: side, weight: weight, color: palette.ink)
                        ClockHands(angles: ClockMath.angles(for: date), style: handStyle(palette, showsSecond: isNear))
                            .frame(width: side * 0.86, height: side * 0.86)
                    }
                    .frame(width: side, height: side)
                    .centered(in: proxy.size, clearOf: keepClear.balancedVertically)
                    if isNear {
                        DateBadge(date: date, palette: palette)
                            .font(.display(side * Self.dateShare, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(faceInsets)
                            .transition(.proximityDetail)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .faceBackdrop(tone: palette.tone) { palette.background.ignoresSafeArea() }
    }

    /// 12 at the top, 3 right, 6 bottom and 9 left, large enough to overlap in the middle.
    private func numerals(side: CGFloat, weight: Font.Weight, color: Color) -> some View {
        let font = Font.display(side * 0.5, weight: weight).width(.condensed)
        let offset = side * 0.27
        return ZStack {
            Text("12").offset(y: -offset)
            Text("3").offset(x: offset * 1.12)
            Text("6").offset(y: offset)
            Text("9").offset(x: -offset * 1.12)
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(color)
    }

    private func handStyle(_ palette: FacePalette, showsSecond: Bool) -> ClockHandsStyle {
        if palette.isNight {
            return .standard(ink: palette.accent, accent: palette.accent, showsSecond: showsSecond)
        }
        let outline: Color = palette.isLight ? palette.ink : .black
        // White hands unless the person picked an accent for them.
        let hand: Color = palette.hasChosenAccent ? palette.accent : .white
        var style = ClockHandsStyle(hour: hand, minute: hand, second: hand, outline: outline)
        style.hourLength = 0.5
        style.minuteLength = 0.9
        style.handWidth = 0.05
        style.showsSecond = showsSecond
        return style
    }
}
