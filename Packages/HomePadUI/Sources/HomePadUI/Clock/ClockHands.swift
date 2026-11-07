import SwiftUI

/// Colors and proportions for a set of clock hands. Lengths and widths are
/// fractions of the dial radius so one style works at every size.
public struct ClockHandsStyle {
    public var hour: Color
    public var minute: Color
    public var second: Color
    /// Optional outline drawn around the hour and minute hands.
    public var outline: Color?
    public var hourLength: CGFloat = 0.52
    public var minuteLength: CGFloat = 0.86
    /// The width of the hands' rounded bodies. Their necks are about a third of it.
    public var handWidth: CGFloat = 0.065
    public var showsSecond = true

    /// - Parameters:
    ///   - hour: Hour hand color.
    ///   - minute: Minute hand and center cap color.
    ///   - second: Second hand color.
    ///   - outline: Optional outline around the hour and minute hands.
    ///   - showsSecond: Draws the second hand.
    public init(hour: Color, minute: Color, second: Color, outline: Color? = nil, showsSecond: Bool = true) {
        self.hour = hour
        self.minute = minute
        self.second = second
        self.outline = outline
        self.showsSecond = showsSecond
    }

    /// Apple Watch style hands: a thin neck from the center and a wide rounded body.
    public static func standard(ink: Color, accent: Color, showsSecond: Bool = true) -> ClockHandsStyle {
        ClockHandsStyle(hour: ink, minute: ink, second: accent, showsSecond: showsSecond)
    }
}

/// Hour, minute and optional second hands for a dial filling the view, the
/// same hands on every HomePad clock (faces, World Clock, widgets).
///
///     ClockHands(angles: ClockMath.angles(for: date), style: .standard(ink: .white, accent: .orange))
public struct ClockHands: View {
    private let angles: ClockMath.HandAngles
    private let style: ClockHandsStyle

    /// - Parameters:
    ///   - angles: Where the hands point. See `ClockMath.angles(for:calendar:)`.
    ///   - style: Colors and proportions.
    public init(angles: ClockMath.HandAngles, style: ClockHandsStyle) {
        self.angles = angles
        self.style = style
    }

    public var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            let width = max(radius * style.handWidth, 3)
            ZStack {
                hand(angle: angles.hour, length: style.hourLength, width: width, color: style.hour, radius: radius)
                hand(angle: angles.minute, length: style.minuteLength, width: width, color: style.minute, radius: radius)
                // A small cap, so the thin necks show between it and the bodies.
                Circle()
                    .fill(style.minute)
                    .frame(width: width * 1.15, height: width * 1.15)
                if style.showsSecond {
                    SecondHand(lengthFraction: 0.94, tailFraction: 0.12)
                        .stroke(style.second, style: StrokeStyle(lineWidth: max(radius * 0.008, 1.5), lineCap: .round))
                        .frame(width: radius * 2, height: radius * 2)
                        .rotationEffect(.degrees(angles.second))
                    Circle()
                        .fill(style.second)
                        .frame(width: width * 0.8, height: width * 0.8)
                }
                Circle()
                    .fill(style.outline ?? Color.black.opacity(0.35))
                    .frame(width: width * 0.35, height: width * 0.35)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func hand(angle: Double, length: CGFloat, width: CGFloat, color: Color, radius: CGFloat) -> some View {
        let shape = HandShape(lengthFraction: length, barWidth: width, stemWidth: max(width * 0.36, min(width, 1.5)))
        return ZStack {
            if let outline = style.outline {
                shape.stroke(outline, lineWidth: max(width * 0.35, 2))
            }
            shape.fill(color)
        }
        .frame(width: radius * 2, height: radius * 2)
        .rotationEffect(.degrees(angle))
        .shadow(color: .black.opacity(0.18), radius: width * 0.6, y: width * 0.3)
    }
}

/// A hand pointing to 12 o'clock inside a square dial rect: a thin neck from
/// the center, about a sixth of the radius long, then a wide rounded body out
/// to the tip, like Apple Watch's hands.
struct HandShape: Shape {
    var lengthFraction: CGFloat
    var barWidth: CGFloat
    var stemWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let tip = radius * lengthFraction
        let stem = min(radius * 0.17, tip * 0.3)
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: center.x - stemWidth / 2, y: center.y - stem - barWidth / 2, width: stemWidth, height: stem + barWidth / 2),
            cornerSize: CGSize(width: stemWidth / 2, height: stemWidth / 2)
        )
        path.addRoundedRect(
            in: CGRect(x: center.x - barWidth / 2, y: center.y - tip, width: barWidth, height: tip - stem),
            cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
        )
        return path
    }
}

/// A thin second hand with a short counterweight tail.
struct SecondHand: Shape {
    var lengthFraction: CGFloat
    var tailFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y + radius * tailFraction))
        path.addLine(to: CGPoint(x: center.x, y: center.y - radius * lengthFraction))
        return path
    }
}
