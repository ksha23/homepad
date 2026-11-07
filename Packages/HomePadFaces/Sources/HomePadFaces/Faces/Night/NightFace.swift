import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.night`: a minimal dim red clock on black for bedrooms. It is
/// always red, so it never lights up a dark room, day or night. From across
/// the room it is a big clock alone. Up close the clock glances smaller and
/// the date and the temperature fade in under it.
struct NightFace: View {
    static let style = FaceOption.style([
        FaceChoice("digital", "Digital", systemImage: "textformat.123"),
        FaceChoice("analog", "Analog", systemImage: "clock"),
    ])

    static let definition = FaceDefinition(
        id: "faces.night", title: "Night", summary: "A dim red clock for the bedroom",
        systemImage: "moon.zzz", sortOrder: 60, options: [style],
        widgets: .besideWidgets(isAlwaysNight: true)
    ) { NightFace() }

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.proximity) private var proximity
    @Environment(\.faceKeepClear) private var keepClear
    @Environment(AppServices.self) private var services

    var body: some View {
        let palette = FacePalette.night
        let isNear = proximity >= .mid
        FaceTimeline(.minute) { date in
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                // One clock at both distances. Its frame and font size animate.
                let scale = isNear ? Self.nearScale : 1
                VStack(spacing: Theme.Spacing.l) {
                    if configuration.value(Self.style) == "analog" {
                        let dial = side * 0.76 * scale
                        ZStack {
                            DialTicks(color: palette.secondary, inset: 0.04)
                            ClockHands(angles: ClockMath.angles(for: date),
                                       style: .standard(ink: palette.ink, accent: palette.accent, showsSecond: false))
                        }
                        .frame(width: dial, height: dial)
                    } else {
                        Text(ClockText.parts(for: date, uses24Hour: ClockText.localeUses24Hour()).joined)
                            .displayFont(min(proxy.size.width * 0.33, side * 0.44) * scale, weight: .medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(palette.ink)
                    }
                    if isNear {
                        HStack(spacing: Theme.Spacing.l) {
                            Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            if let weather = services.weather.current {
                                Label("\(Int(weather.temperature.rounded()))°", systemImage: weather.symbolName)
                            }
                        }
                        .font(.display(side * 0.045, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .transition(.proximityDetail)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            // Centered clear of the widgets and the Now Playing pill.
            .padding(keepClear)
            .opacity(0.6)
        }
        .faceBackdrop(tone: .black) { Color.black.ignoresSafeArea() }
    }

    /// How much smaller the clock is up close.
    static let nearScale: CGFloat = 0.64
}
