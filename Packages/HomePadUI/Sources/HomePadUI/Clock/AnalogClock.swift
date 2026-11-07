import SwiftUI

/// A round analog clock for any time zone, light by day and dark by night
/// like Apple's World Clock. It uses the same `ClockHands` and `DialTicks`
/// as the analog faces, so every clock in HomePad matches.
///
///     AnalogClock(date: now, timeZone: tokyo, isDaytime: false)
///     AnalogClock(date: now, dial: .numerals, colors: .init(face: .black, ink: .red, accent: .red))
public struct AnalogClock: View {
    /// What the dial shows besides the hands.
    public enum Dial: Sendable {
        /// Minute ticks and hour numerals 1 to 12.
        case numerals
        /// Minute ticks only.
        case ticks
    }

    /// The dial's colors.
    public struct Colors {
        public var face: Color
        public var ink: Color
        public var accent: Color
        /// Optional ring around the dial, for dark surfaces such as night mode.
        public var rim: Color?

        /// - Parameters:
        ///   - face: Dial background.
        ///   - ink: Hands, ticks and numerals.
        ///   - accent: Second hand.
        ///   - rim: Optional ring around the dial.
        public init(face: Color, ink: Color, accent: Color = .orange, rim: Color? = nil) {
            self.face = face
            self.ink = ink
            self.accent = accent
            self.rim = rim
        }

        /// A white dial with black hands, for daytime.
        public static let day = Colors(face: Color(white: 0.96), ink: .black)
        /// A charcoal dial with white hands, for nighttime.
        public static let night = Colors(face: Color(white: 0.14), ink: .white)
    }

    private let date: Date
    private let calendar: Calendar
    private let dial: Dial
    private let showsSeconds: Bool
    private let colors: Colors

    /// - Parameters:
    ///   - date: The moment to show. Drive it from a `TimelineView`.
    ///   - timeZone: The clock's time zone.
    ///   - dial: `.ticks` or `.numerals`.
    ///   - showsSeconds: Draws the second hand.
    ///   - isDaytime: Picks `.day` or `.night` colors when `colors` is nil.
    ///   - colors: Explicit colors, for example a face's night palette.
    public init(
        date: Date, timeZone: TimeZone = .current, dial: Dial = .ticks, showsSeconds: Bool = false,
        isDaytime: Bool = true, colors: Colors? = nil
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.date = date
        self.calendar = calendar
        self.dial = dial
        self.showsSeconds = showsSeconds
        self.colors = colors ?? (isDaytime ? .day : .night)
    }

    public var body: some View {
        ZStack {
            Circle().fill(colors.face)
            if let rim = colors.rim {
                Circle().strokeBorder(rim, lineWidth: 2)
            }
            DialTicks(color: colors.ink.opacity(0.5), inset: 0.06)
            if dial == .numerals {
                DialNumerals(radiusFraction: 0.7) { numeral, radius in
                    Text("\(numeral)")
                        .font(.display(radius * 0.17))
                        .foregroundStyle(colors.ink)
                }
            }
            ClockHands(angles: ClockMath.angles(for: date, calendar: calendar),
                       style: .standard(ink: colors.ink, accent: colors.accent, showsSecond: showsSeconds))
                .padding(4)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilityTime)
    }

    private var accessibilityTime: String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
