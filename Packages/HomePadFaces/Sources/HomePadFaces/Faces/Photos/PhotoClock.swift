import HomePadCore
import HomePadUI
import SwiftUI

/// The time on the Photos face, placed by `PhotoClockLayout`. The depth
/// style draws tall numerals of frosted glass across the photo, like
/// HomeView's (`GlassNumerals`), red and flat at night. The classic style
/// draws a white clock. From across the room the time is all there is. Up
/// close it shrinks into place as the date fades in. The time is one view,
/// drawn at its far size, so it glides between the two instead of stepping.
/// With the depth effect the face draws the time and the date apart, the
/// date over the subject, so only the numerals go behind it.
struct PhotoClock: View {
    let isDepthStyle: Bool
    let tint: Color
    let layout: PhotoClockLayout
    let isNear: Bool
    var isNight = false
    var showsTime = true
    var showsDate = true

    var body: some View {
        FaceTimeline(.minute) { date in
            let time = ClockText.parts(for: date, uses24Hour: ClockText.localeUses24Hour()).joined
            ZStack(alignment: .topLeading) {
                if isNear, showsDate {
                    Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.display(layout.dateSize, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .flattenedShadow(color: .black.opacity(isDepthStyle ? 0.25 : 0.35), radius: 8, y: 2)
                        .frame(width: layout.date.width, height: layout.date.height)
                        .position(x: layout.date.midX, y: layout.date.midY)
                        .transition(.proximityDetail)
                }
                Group {
                    if !showsTime {
                        EmptyView()
                    } else if isDepthStyle, !isNight {
                        GlassNumerals(line: GlyphLine(time, font: Self.depthUIFont), tint: tint)
                            .accessibilityElement()
                            .accessibilityLabel(time)
                    } else if isDepthStyle {
                        depthTime(time)
                    } else {
                        classicTime(time)
                    }
                }
                .distanceFrame(far: layout.farLine, near: layout.nearLine, isNear: isNear)
            }
            .frame(width: layout.viewSize.width, height: layout.viewSize.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private func depthTime(_ time: String) -> some View {
        Text(time)
            .font(Self.depthFont(layout.fontSize))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.97), tint.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            .overlay {
                Text(time)
                    .font(Self.depthFont(layout.fontSize))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center))
                    .blendMode(.plusLighter)
            }
            // Stays live: flattened, the plus-lighter highlight above blends
            // inside the flattened layer and the numerals' tops turn white.
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
    }

    private func classicTime(_ time: String) -> some View {
        Text(time)
            .font(.display(layout.fontSize, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(tint)
            .flattenedShadow(color: .black.opacity(0.35), radius: 16, y: 4)
    }

    /// Tall compressed numerals like the iPhone Lock Screen depth clock. SF Pro
    /// Rounded has no compressed width, so this style uses SF Pro.
    static func depthFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).width(.compressed)
    }

    /// `depthFont` for the glass numerals' outlines, which scale to their frame.
    static let depthUIFont = UIFont.systemFont(ofSize: 100, weight: .semibold, width: .compressed)
}
