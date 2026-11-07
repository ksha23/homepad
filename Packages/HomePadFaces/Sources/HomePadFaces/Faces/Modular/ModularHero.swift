import HomePadUI
import SwiftUI

/// The top of the Modular face. Analog: the date with a big day number
/// beside a dial, like HomeView's info face. Digital: a date line over a big
/// time, like the Lock Screen.
///
/// From across the room the two parts fill the face. Each is drawn at that
/// size and shrinks into its place up close (`distanceFrame`), so walking up
/// glides them into the top half instead of laying them out again.
struct ModularHero: View {
    let date: Date
    let isDigital: Bool
    let showsSeconds: Bool
    let palette: FacePalette
    /// The parts from across the room. They are drawn at this size.
    let far: ModularHeroLayout
    /// The parts up close.
    let near: ModularHeroLayout
    let isNear: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isDigital {
                dateLine
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .distanceFrame(far: far.date, near: near.date, isNear: isNear, anchor: .leading)
                time
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .distanceFrame(far: far.clock, near: near.clock, isNear: isNear, anchor: .leading)
            } else {
                analogDate
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .distanceFrame(far: far.date, near: near.date, isNear: isNear, anchor: .leading)
                dial
                    .distanceFrame(far: far.clock, near: near.clock, isNear: isNear)
            }
        }
    }

    // MARK: Analog

    private var analogDate: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: far.line * 0.25) {
                Text(date, format: .dateTime.weekday(.abbreviated)).foregroundStyle(palette.ink)
                Text(date, format: .dateTime.month(.abbreviated)).foregroundStyle(palette.accent)
            }
            .font(.display(far.line, weight: .semibold))
            Text(date, format: .dateTime.day())
                .font(.display(far.numeral, weight: .bold))
                .foregroundStyle(palette.ink)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private var dial: some View {
        ZStack {
            DialTicks(color: palette.secondary)
            DialNumerals(radiusFraction: 0.74) { numeral, radius in
                Text("\(numeral)")
                    .font(.display(radius * 0.19, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }
            ClockHands(angles: ClockMath.angles(for: date), style: .standard(
                ink: palette.isNight ? palette.accent : palette.ink, accent: palette.accent, showsSecond: showsSeconds))
        }
    }

    // MARK: Digital

    private var dateLine: some View {
        HStack(spacing: far.line * 0.3) {
            Text(date, format: .dateTime.weekday(.wide)).foregroundStyle(palette.accent)
            Text(date, format: .dateTime.month(.wide).day()).foregroundStyle(palette.ink)
        }
        .font(.display(far.line, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private var time: some View {
        let parts = ClockText.parts(for: date, uses24Hour: ClockText.localeUses24Hour())
        return HStack(alignment: .firstTextBaseline, spacing: far.line * 0.3) {
            Text(parts.joined)
                .font(.display(far.numeral, weight: .semibold))
                .foregroundStyle(palette.ink)
                .contentTransition(.numericText())
            if let period = parts.period, showsSeconds {
                Text(period)
                    .font(.display(far.line, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .transition(.proximityDetail)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}
