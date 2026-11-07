import SwiftUI

/// Drawn landscapes that stand in for photos in the simulator: a sky gradient,
/// a sun or moon, and layered hills, varied by index.
struct DemoPhotoArt: View {
    let index: Int

    private static let skies: [(Color, Color)] = [
        (Color(red: 0.98, green: 0.55, blue: 0.35), Color(red: 0.99, green: 0.84, blue: 0.55)),
        (Color(red: 0.25, green: 0.55, blue: 0.90), Color(red: 0.70, green: 0.86, blue: 0.98)),
        (Color(red: 0.36, green: 0.22, blue: 0.55), Color(red: 0.95, green: 0.55, blue: 0.55)),
        (Color(red: 0.05, green: 0.10, blue: 0.25), Color(red: 0.20, green: 0.30, blue: 0.55)),
        (Color(red: 0.55, green: 0.80, blue: 0.85), Color(red: 0.92, green: 0.96, blue: 0.90)),
        (Color(red: 0.90, green: 0.40, blue: 0.30), Color(red: 0.40, green: 0.20, blue: 0.40)),
    ]

    private static let hills: [Color] = [
        Color(red: 0.20, green: 0.40, blue: 0.30), Color(red: 0.30, green: 0.25, blue: 0.40),
        Color(red: 0.15, green: 0.30, blue: 0.45), Color(red: 0.35, green: 0.45, blue: 0.25),
    ]

    var body: some View {
        Canvas { context, size in
            let sky = Self.skies[(index + index / Self.skies.count) % Self.skies.count]
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [sky.0, sky.1]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let sunX = size.width * (0.2 + Double((index * 37) % 60) / 100)
            let sunRadius = min(size.width, size.height) * 0.09
            context.fill(Path(ellipseIn: CGRect(x: sunX - sunRadius, y: size.height * 0.28 - sunRadius, width: sunRadius * 2, height: sunRadius * 2)),
                         with: .color(.white.opacity(0.85)))
            for layer in 0..<3 {
                let base = size.height * (0.55 + Double(layer) * 0.14)
                let amplitude = size.height * (0.08 - Double(layer) * 0.015)
                let phase = Double(index * 13 + layer * 29)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for step in 0...40 {
                    let x = size.width * Double(step) / 40
                    let y = base - amplitude * sin(Double(step) / 40 * .pi * (1.5 + Double(layer)) + phase)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                let color = Self.hills[(index + layer) % Self.hills.count].opacity(0.55 + Double(layer) * 0.2)
                context.fill(path, with: .color(color))
            }
        }
        .accessibilityLabel("Demo photo")
    }
}
