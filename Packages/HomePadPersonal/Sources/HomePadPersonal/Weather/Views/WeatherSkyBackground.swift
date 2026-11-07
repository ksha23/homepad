import HomePadCore
import SwiftUI

/// The animated sky behind the Weather app and widget: a condition gradient,
/// slowly drifting clouds, stars on clear nights, and falling rain or snow.
/// Motion stops for Reduce Motion, night mode, thumbnails and widgets, and
/// slows to a few frames a second behind the Home Screen's frost.
struct WeatherSkyBackground: View {
    let condition: WeatherConditionKind
    let isDaylight: Bool
    /// False for widgets. A sky redrawn 30 times a second keeps the whole Home
    /// Screen updating every frame, and widgets are static, like Apple's.
    var isAnimated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayCondition) private var displayCondition
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.isFrosted) private var isFrosted

    var body: some View {
        let isStill = !isAnimated || reduceMotion || isThumbnail || displayCondition == .night || displayCondition == .sleeping
        ZStack {
            LinearGradient(colors: WeatherPalette.sky(for: condition, isDaylight: isDaylight), startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: isFrosted ? 0.5 : 1.0 / 30.0, paused: isStill)) { timeline in
                let time = isStill ? 0 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    if !isDaylight && condition.cloudiness < 0.5 { drawStars(in: &context, size: size, time: time) }
                    drawClouds(in: &context, size: size, time: time)
                    drawPrecipitation(in: &context, size: size, time: time)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: Layers

    private func drawStars(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<90 {
            let x = Self.noise(index, 1) * size.width
            let y = Self.noise(index, 2) * size.height * 0.6
            let twinkle = 0.5 + 0.5 * sin(time * (0.5 + Self.noise(index, 3)) + Double(index))
            let radius = 0.6 + Self.noise(index, 4) * 1.4
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                         with: .color(.white.opacity(0.3 + 0.6 * twinkle)))
        }
    }

    private func drawClouds(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let cloudiness = condition.cloudiness
        guard cloudiness > 0 else { return }
        let count = Int(3 + cloudiness * 7)
        let tint = WeatherPalette.cloud(isDaylight: isDaylight, condition: condition)
        // All clouds go into one layer that is laid on the sky at no more than
        // `cloudCeiling`. Drawn straight onto the sky, overlapping puffs added
        // up to solid white, and the white labels and glass buttons over them
        // disappeared.
        var clouds = context
        clouds.opacity = Self.cloudCeiling
        clouds.drawLayer { layer in
            layer.addFilter(.blur(radius: 28))
            drawCloudPuffs(in: &layer, size: size, time: time, count: count, cloudiness: cloudiness, tint: tint)
        }
    }

    /// The brightest the clouds get over the sky, so white text stays readable.
    static let cloudCeiling = 0.6

    private func drawCloudPuffs(in layer: inout GraphicsContext, size: CGSize, time: TimeInterval,
                                count: Int, cloudiness: Double, tint: Color) {
        for index in 0..<count {
            let width = size.width * (0.35 + Self.noise(index, 5) * 0.4)
            let speed = 6 + Self.noise(index, 6) * 10
            let span = size.width + width * 2
            let x = (Self.noise(index, 7) * span + time * speed).truncatingRemainder(dividingBy: span) - width
            let y = size.height * (Self.noise(index, 8) * 0.45 * cloudiness) - width * 0.15
            // Within the layer, so a lone cloud still reaches about the
            // brightness it had before the ceiling.
            let opacity = min(1, (0.25 + cloudiness * 0.5 * (0.6 + Self.noise(index, 9) * 0.4)) / Self.cloudCeiling * 0.8)
            for puff in 0..<4 {
                let px = x + Double(puff) * width * 0.22
                let pr = width * (0.28 + Self.noise(index * 4 + puff, 10) * 0.18)
                let py = y + sin(Double(puff) * 1.7) * pr * 0.25
                layer.fill(Path(ellipseIn: CGRect(x: px, y: py, width: pr * 2, height: pr * 1.3)), with: .color(tint.opacity(opacity)))
            }
        }
    }

    private func drawPrecipitation(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        switch condition.precipitation {
        case .none:
            return
        case .rain, .heavyRain:
            let count = condition.precipitation == .heavyRain ? 220 : 120
            for index in 0..<count {
                let speed = 700 + Self.noise(index, 11) * 400
                let length = 18 + Self.noise(index, 12) * 22
                let x = Self.noise(index, 13) * (size.width + 80)
                let y = (Self.noise(index, 14) * size.height + time * speed).truncatingRemainder(dividingBy: size.height + length) - length
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x - length * 0.18, y: y + length))
                context.stroke(path, with: .color(.white.opacity(0.22 + Self.noise(index, 15) * 0.25)), lineWidth: 1.4)
            }
        case .snow, .sleet:
            let isSleet = condition.precipitation == .sleet
            for index in 0..<(isSleet ? 140 : 100) {
                let speed = (isSleet ? 220 : 45) + Self.noise(index, 16) * 40
                let radius = isSleet ? 1.5 : 2 + Self.noise(index, 17) * 3
                let sway = isSleet ? 0 : sin(time * 0.8 + Double(index)) * 18
                let x = Self.noise(index, 18) * size.width + sway
                let y = (Self.noise(index, 19) * size.height + time * speed).truncatingRemainder(dividingBy: size.height + 10) - 10
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(0.55 + Self.noise(index, 20) * 0.4)))
            }
        }
    }

    /// Deterministic 0...1 pseudo-random value, so particles keep their places between frames.
    private static func noise(_ index: Int, _ salt: Int) -> Double {
        let value = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43_758.5453
        return value - value.rounded(.down)
    }
}
