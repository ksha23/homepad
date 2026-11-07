import SwiftUI

/// Text pressed into the surface it sits on: the edge facing the light falls
/// into shadow and the far edge catches a highlight.
struct EmbossedText: View {
    let text: String
    let font: Font
    let surface: Color
    /// Where the light comes from, in radians counterclockwise from the right
    /// (pi/2 is straight above, 3pi/4 is the top left).
    var lightAngle: Double = .pi * 0.75
    var depth: CGFloat = 2
    var highlight: Color = .white.opacity(0.9)
    var shadow: Color = .black.opacity(0.3)

    var body: some View {
        let dx = CGFloat(cos(lightAngle)) * depth
        let dy = -CGFloat(sin(lightAngle)) * depth
        ZStack {
            Text(text).foregroundStyle(highlight).offset(x: -dx, y: -dy).blur(radius: depth * 0.35)
            Text(text).foregroundStyle(shadow).offset(x: dx, y: dy).blur(radius: depth * 0.5)
            Text(text).foregroundStyle(surface)
        }
        .font(font)
    }
}
