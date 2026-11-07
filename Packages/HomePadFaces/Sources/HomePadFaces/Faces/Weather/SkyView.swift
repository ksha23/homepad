import HomePadCore
import SwiftUI

/// The animated sky behind the Weather face: a gradient for the condition
/// and time of day, the sun or moon, stars, drifting clouds, rain or snow,
/// and the occasional lightning flash.
///
/// Clouds drift a couple of points a second, so they are redrawn a few times a
/// second (`cloudFrameRate`) instead of by a full-rate animation that re-blurred
/// seven large clouds on every frame all day. Rain and snow come from a particle
/// emitter. Motion stops in thumbnails, behind the Home Screen's frost, beside
/// the face on the wall and while the display is dimmed (`faceAllowsMotion`),
/// and the clouds freeze where they are.
struct SkyView: View {
    let condition: SkyCondition
    let time: SkyTime
    /// The Animated style. False for the Still style and in thumbnails.
    let isAnimated: Bool

    @Environment(\.faceAllowsMotion) private var allowsMotion
    @State private var flash = false

    /// Clouds move about 2 points a second, so a few frames a second is smooth.
    static let cloudFrameRate: Double = 4
    /// Seconds for the clouds to drift one way. They drift back over the same time.
    static let cloudDriftSeconds: Double = 90

    var body: some View {
        let colors = SkyPalette.colors(condition, time)
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: [Color(hex: colors.top), Color(hex: colors.bottom)], startPoint: .top, endPoint: .bottom)
                if time == .night && (condition == .clear || condition == .partlyCloudy) {
                    StarField(seed: 7).opacity(0.85)
                }
                if (condition == .clear || condition == .partlyCloudy) && (time == .day || time == .night) {
                    lightSource(size: size)
                }
                if isAnimated {
                    FaceTimeline(.frames(Self.cloudFrameRate)) { date in
                        clouds(size: size, phase: Self.driftPhase(at: date))
                    }
                } else {
                    clouds(size: size, phase: -1)
                }
                if isAnimated, condition == .rain || condition == .thunder || condition == .snow {
                    // Stops making drops rather than disappearing, so the sky empties gently.
                    PrecipitationView(kind: condition == .snow ? .snow : .rain, isRunning: allowsMotion)
                }
                if condition == .thunder {
                    Color.white.opacity(flash ? 0.35 : 0).blendMode(.plusLighter)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .task(id: condition == .thunder && isAnimated && allowsMotion) {
            guard condition == .thunder, isAnimated, allowsMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 6...14)))
                withAnimation(.easeOut(duration: 0.08)) { flash = true }
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.easeIn(duration: 0.6)) { flash = false }
            }
        }
    }

    private func lightSource(size: CGSize) -> some View {
        let isNight = time == .night
        let center = CGPoint(x: size.width * 0.78, y: size.height * (isNight ? 0.16 : 0.12))
        let radius = max(size.width, size.height) * (isNight ? 0.04 : 0.06)
        return ZStack {
            RadialGradient(colors: [Color.white.opacity(isNight ? 0.18 : 0.55), .clear], center: .center,
                           startRadius: 0, endRadius: radius * 7)
                .frame(width: radius * 14, height: radius * 14)
            Circle()
                .fill(isNight ? Color(hex: "#F4F1E4") : Color(hex: "#FFF6D6"))
                .frame(width: radius * 2, height: radius * 2)
                .blur(radius: isNight ? 0.5 : 6)
        }
        .position(center)
    }

    /// Where the clouds are in their drift, from -1 to 1 and back, at a steady
    /// speed like the linear back-and-forth animation it replaces.
    static func driftPhase(at date: Date) -> CGFloat {
        let period = 2 * cloudDriftSeconds
        let position = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / cloudDriftSeconds
        return CGFloat(position <= 1 ? -1 + 2 * position : 3 - 2 * position)
    }

    /// - Parameter phase: -1 to 1, how far along their drift the clouds are.
    private func clouds(size: CGSize, phase: CGFloat) -> some View {
        let cloud = SkyPalette.clouds(condition, time)
        return ZStack {
            ForEach(0..<condition.cloudCount, id: \.self) { index in
                let layout = CloudLayout.puff(index, condition: condition)
                Ellipse()
                    .fill(cloud.tone.color.opacity(cloud.opacity * layout.opacity))
                    .frame(width: size.width * layout.width, height: size.width * layout.width * layout.aspect)
                    .blur(radius: size.width * CloudLayout.blur)
                    .position(x: size.width * layout.x, y: size.height * layout.y)
                    .offset(x: phase * size.width * layout.drift)
            }
        }
    }
}

/// The shade the Weather face lays between its sky and its white text, top
/// to bottom as dark as `SkyPalette.textShade` works out for the sky's own
/// colors. A dark sky gets none, so nothing is drawn there. It goes with the
/// text (`faceForeground()`), so behind the Home Screen the sky shows as it is.
struct SkyTextShade: View {
    let condition: SkyCondition
    let time: SkyTime

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let shade = SkyPalette.textShade(condition, time,
                                             aspectRatio: size.height > 0 ? size.width / size.height : 1)
            if shade.contains(where: { $0 > 0 }) {
                LinearGradient(colors: shade.map { Color.black.opacity($0) }, startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A sprinkle of stars drawn once with a Canvas.
private struct StarField: View {
    let seed: Int

    var body: some View {
        Canvas { context, size in
            var generator = SplitMix(seed: UInt64(seed))
            for _ in 0..<90 {
                let x = CGFloat(generator.unit()) * size.width
                let y = CGFloat(generator.unit()) * size.height * 0.6
                let radius = CGFloat(0.6 + generator.unit() * 1.4)
                let alpha = 0.3 + generator.unit() * 0.7
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }
}
