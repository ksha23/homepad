import HomePadCore
import HomePadUI
import SwiftUI

/// A drawn stand-in for a camera feed, so the demo backend's cameras look alive in
/// the simulator. The scene depends on the camera's name and the time of day.
struct DemoCameraFeedView: View {
    let camera: HomeCamera
    var date: Date?
    /// The time drawn in the corner, as cameras print it on their video.
    /// Snapshots leave it off and get an age label instead.
    var showsClock = true

    var body: some View {
        if let date {
            scene(at: date)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                scene(at: context.date)
            }
        }
    }

    private func scene(at date: Date) -> some View {
        Canvas { context, size in
            let hour = Calendar.current.component(.hour, from: date)
            let isNight = hour < 7 || hour >= 19
            let sky = isNight ? [Color(red: 0.05, green: 0.07, blue: 0.16), Color(red: 0.12, green: 0.14, blue: 0.24)]
                : [Color(red: 0.47, green: 0.66, blue: 0.86), Color(red: 0.78, green: 0.86, blue: 0.92)]
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let horizon = size.height * 0.58
            let ground = CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)
            context.fill(Path(ground), with: .color(isNight ? Color(red: 0.08, green: 0.14, blue: 0.09) : Color(red: 0.32, green: 0.5, blue: 0.28)))
            drawProps(in: &context, size: size, horizon: horizon, isNight: isNight)
            // Camera vignette and a faint scan of noise.
            context.fill(Path(rect), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.45)]),
                                                         center: CGPoint(x: size.width / 2, y: size.height / 2),
                                                         startRadius: size.width * 0.3, endRadius: size.width * 0.75))
            let flicker = Double(Int(date.timeIntervalSince1970) % 3) * 0.015
            context.fill(Path(rect), with: .color(.white.opacity(flicker)))
        }
        .overlay(alignment: .topTrailing) {
            if showsClock {
                Text(date, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(Theme.Spacing.s)
            }
        }
        .accessibilityLabel("Demo feed for \(camera.name)")
    }

    private func drawProps(in context: inout GraphicsContext, size: CGSize, horizon: CGFloat, isNight: Bool) {
        let name = camera.name.lowercased()
        let wall = isNight ? Color(red: 0.18, green: 0.16, blue: 0.15) : Color(red: 0.86, green: 0.8, blue: 0.7)
        let accent = isNight ? Color(red: 0.95, green: 0.78, blue: 0.4) : Color(red: 0.36, green: 0.22, blue: 0.16)
        if name.contains("living") {
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)), with: .color(wall))
            context.fill(Path(roundedRect: CGRect(x: size.width * 0.58, y: size.height * 0.12, width: size.width * 0.3, height: size.height * 0.34), cornerRadius: 6),
                         with: .color(isNight ? Color(red: 0.1, green: 0.12, blue: 0.22) : Color(red: 0.6, green: 0.78, blue: 0.92)))
            context.fill(Path(roundedRect: CGRect(x: size.width * 0.12, y: horizon - size.height * 0.12, width: size.width * 0.42, height: size.height * 0.22), cornerRadius: 18),
                         with: .color(Color(red: 0.32, green: 0.38, blue: 0.5)))
        } else if name.contains("drive") {
            var road = Path()
            road.move(to: CGPoint(x: size.width * 0.35, y: horizon))
            road.addLine(to: CGPoint(x: size.width * 0.62, y: horizon))
            road.addLine(to: CGPoint(x: size.width * 0.95, y: size.height))
            road.addLine(to: CGPoint(x: size.width * 0.05, y: size.height))
            context.fill(road, with: .color(Color(white: isNight ? 0.18 : 0.55)))
            context.fill(Path(roundedRect: CGRect(x: size.width * 0.4, y: horizon + size.height * 0.08, width: size.width * 0.22, height: size.height * 0.14), cornerRadius: 12),
                         with: .color(Color(red: 0.62, green: 0.1, blue: 0.12)))
        } else if name.contains("door") || name.contains("porch") || name.contains("front") {
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: horizon + 10)), with: .color(wall))
            context.fill(Path(roundedRect: CGRect(x: size.width * 0.4, y: size.height * 0.16, width: size.width * 0.2, height: horizon - size.height * 0.16 + 10), cornerRadius: 4),
                         with: .color(accent))
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.55, y: size.height * 0.4, width: 8, height: 8)), with: .color(.yellow.opacity(0.8)))
        } else {
            for index in 0..<9 {
                let x = size.width * (0.05 + Double(index) * 0.11)
                context.fill(Path(CGRect(x: x, y: horizon - size.height * 0.1, width: 8, height: size.height * 0.1)), with: .color(accent.opacity(0.8)))
            }
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.66, y: horizon - size.height * 0.36, width: size.width * 0.2, height: size.height * 0.3)),
                         with: .color(Color(red: 0.16, green: 0.36, blue: 0.2)))
        }
    }
}
