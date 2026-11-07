import SwiftUI

/// Sixty minute ticks around the edge of a round dial, drawn in one Canvas pass.
///
///     DialTicks(color: .white.opacity(0.6))
public struct DialTicks: View {
    private let color: Color
    private let inset: CGFloat

    /// - Parameters:
    ///   - color: Color of the hour ticks. Minute ticks use a fainter version.
    ///   - inset: Inset of the ticks from the dial edge, as a fraction of the radius.
    public init(color: Color, inset: CGFloat = 0.02) {
        self.color = color
        self.inset = inset
    }

    public var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 * (1 - inset)
            for tick in 0..<60 {
                let major = tick % 5 == 0
                let length = radius * (major ? 0.075 : 0.04)
                let fraction = Double(tick) / 60
                var path = Path()
                path.move(to: ClockMath.point(fraction: fraction, radius: radius, center: center))
                path.addLine(to: ClockMath.point(fraction: fraction, radius: radius - length, center: center))
                context.stroke(path, with: .color(major ? color : color.opacity(0.55)),
                               style: StrokeStyle(lineWidth: max(radius * (major ? 0.012 : 0.006), 1), lineCap: .round))
            }
        }
    }
}

/// Where `DialNumerals` puts the numerals.
public enum DialNumeralPath: Equatable, Sendable {
    /// Around a circle, this far from the center as a fraction of the radius.
    case circle(radiusFraction: CGFloat)
    /// Along the edge of the view's own rounded rectangle, `inset` points in
    /// to the numerals' centers, with corners of `cornerRadius` points. Each
    /// numeral sits where the line from the center toward its hour meets that
    /// edge, so the numerals follow a rounded screen of any shape, like
    /// HomeView's full-screen dials. Inset by about half a numeral's width.
    case roundedRect(inset: CGFloat, cornerRadius: CGFloat)

    /// Where the numeral at `fraction` of the way around (0 is 12) goes in a view of `size`.
    public func point(fraction: Double, in size: CGSize) -> CGPoint {
        switch self {
        case .circle(let radiusFraction):
            let radius = min(size.width, size.height) / 2
            return ClockMath.point(fraction: fraction, radius: radius * radiusFraction,
                                   center: CGPoint(x: size.width / 2, y: size.height / 2))
        case .roundedRect(let inset, let cornerRadius):
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            return ClockMath.point(fraction: fraction, onRoundedRect: rect, cornerRadius: cornerRadius)
        }
    }
}

/// The twelve hour numerals placed around a dial. The label closure gets
/// the numeral and the dial radius (half the view's shorter side), so the
/// font can scale with the dial.
///
///     DialNumerals(radiusFraction: 0.74) { numeral, radius in
///         Text("\(numeral)").font(.display(radius * 0.17))
///     }
public struct DialNumerals<Label: View>: View {
    private let path: DialNumeralPath
    private let numerals: [Int]
    private let label: (Int, CGFloat) -> Label

    /// - Parameters:
    ///   - radiusFraction: Distance from the center as a fraction of the radius.
    ///   - numerals: Which numerals to draw, 1 through 12 by default.
    ///   - label: Draws one numeral, given the numeral and the dial radius.
    public init(radiusFraction: CGFloat = 0.78, numerals: [Int] = Array(1...12),
                @ViewBuilder label: @escaping (Int, CGFloat) -> Label) {
        self.init(path: .circle(radiusFraction: radiusFraction), numerals: numerals, label: label)
    }

    /// - Parameters:
    ///   - path: Around a circle or along the view's rounded rectangle.
    ///   - numerals: Which numerals to draw, 1 through 12 by default.
    ///   - label: Draws one numeral, given the numeral and the dial radius.
    public init(path: DialNumeralPath, numerals: [Int] = Array(1...12),
                @ViewBuilder label: @escaping (Int, CGFloat) -> Label) {
        self.path = path
        self.numerals = numerals
        self.label = label
    }

    public var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            ForEach(numerals, id: \.self) { numeral in
                label(numeral, radius)
                    .position(path.point(fraction: Double(numeral) / 12, in: proxy.size))
            }
        }
    }
}
