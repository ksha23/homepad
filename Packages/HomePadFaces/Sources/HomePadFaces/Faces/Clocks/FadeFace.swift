import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.fade`: a sundial-inspired clock. Numerals near the hour are lit
/// and the rest fade away, and the light sweeps across the face from
/// morning to evening. Up close the second hand and the date fade in.
struct FadeFace: View {
    static let color = FaceOption.color([.rose, .sand, .sage, .ocean, .lavender, .porcelain], default: .rose)

    static let definition = FaceDefinition(
        id: "faces.fade", title: "Fade", summary: "A sundial whose numerals fade in and out over the day",
        systemImage: "sun.dust", sortOrder: 43, options: [color],
        // The numerals' ring, the hands and the date between them.
        widgets: .around(.centered(width: 0.84, height: 0.84), landscapeFill: .trailingColumns)
    ) { FadeFace() }

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity
    @Environment(\.faceKeepClear) private var keepClear

    var body: some View {
        let palette = FacePalette.resolve(configuration.colors(Self.color), condition: condition)
        let isNear = proximity >= .mid
        FaceTimeline(isNear ? .second : .minute) { date in
            let hour = FadeCurve.hourOfDay(date)
            let daylight = FadeCurve.daylight(hour: hour)
            let light = FadeCurve.lightAngle(hour: hour)
            let angles = ClockMath.angles(for: date)
            GeometryReader { proxy in
                // Clear of the Now Playing pill while it shows: smaller, still centered.
                let area = proxy.size.leaving(keepClear.balancedVertically)
                let side = min(area.width, area.height) * 0.94
                ZStack {
                    Rectangle().fill(palette.background).ignoresSafeArea()
                    if !palette.isNight {
                        sunGlow(light: light, daylight: daylight, size: proxy.size)
                    }
                    ZStack {
                        DialNumerals(radiusFraction: 0.8) { numeral, radius in
                            numeralLabel(numeral, radius: radius, palette: palette, light: light)
                                .opacity(FadeCurve.opacity(numeral: numeral, hourPosition: angles.hour / 30, daylight: daylight))
                        }
                        // Between the center and the 6, clear of the hands at most times.
                        if isNear {
                            DateBadge(date: date, palette: palette)
                                .font(.display(side * 0.035, weight: .semibold))
                                .position(x: side * 0.5, y: side * 0.7)
                                .transition(.proximityDetail)
                        }
                        ClockHands(angles: angles, style: .standard(
                            ink: palette.isNight ? palette.accent : palette.ink, accent: palette.accent, showsSecond: isNear))
                    }
                    .frame(width: side, height: side)
                    .centered(in: proxy.size, clearOf: keepClear.balancedVertically)
                    // Behind the Home Screen the face is its color and the sun's light.
                    .faceForeground()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .animation(.easeInOut(duration: 2), value: hour)
            }
        }
        // The sun's light is soft, so the background's color sets the tone.
        .backdropTone(palette.tone)
    }

    @ViewBuilder
    private func numeralLabel(_ value: Int, radius: CGFloat, palette: FacePalette, light: Double) -> some View {
        let font = Font.display(radius * 0.24, weight: .regular)
        if palette.isNight {
            Text("\(value)").font(font).foregroundStyle(palette.secondary)
        } else {
            // Pressed into the surface, in the text color when one is chosen.
            EmbossedText(text: "\(value)", font: font, surface: palette.hasChosenText ? palette.ink : palette.top,
                         lightAngle: light, depth: radius * 0.01)
        }
    }

    /// A soft wash of light from the side the sun is on.
    private func sunGlow(light: Double, daylight: Double, size: CGSize) -> some View {
        let center = UnitPoint(x: 0.5 + cos(light) * 0.6, y: 0.5 - sin(light) * 0.6)
        return RadialGradient(colors: [.white.opacity(0.18 + 0.3 * daylight), .clear],
                              center: center, startRadius: 0, endRadius: max(size.width, size.height) * 0.9)
            .ignoresSafeArea()
    }
}
