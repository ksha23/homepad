import HomePadCore
import HomePadUI
import SwiftUI

/// The Calendar face's Up Next style: the date in big type. From across the
/// room it is the date alone, larger and centered. Up close it moves aside
/// (to the leading side in landscape, the top in portrait) and what is still
/// to come today fades in beside it. Its type sizes animate, so it glides.
struct CalendarUpNext: View {
    let date: Date
    /// Today's events the person may see (personal ones only once recognized).
    let events: [CalendarItem]
    let palette: FacePalette
    let isNear: Bool

    @Environment(\.faceInsets) private var faceInsets

    /// How much larger the date is from across the room.
    static let farScale: CGFloat = 1.3

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width
            let side = min(proxy.size.width, proxy.size.height)
            let content = CGSize(width: proxy.size.width - faceInsets.leading - faceInsets.trailing,
                                 height: proxy.size.height - faceInsets.top - faceInsets.bottom)
            let layout = isPortrait ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xl))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.xl))
            ZStack(alignment: .topLeading) {
                Rectangle().fill(palette.background).ignoresSafeArea()
                layout {
                    dateBlock(side: side * (isNear ? 1 : Self.farScale))
                        .frame(width: isNear && !isPortrait ? content.width * 0.4 : content.width,
                               height: isNear && isPortrait ? content.height * 0.38 : content.height,
                               alignment: isNear ? .topLeading : .center)
                    if isNear {
                        agenda(side: side)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.proximityDetail)
                    }
                }
                .padding(faceInsets)
            }
        }
    }

    /// The weekday, the day's number and the month. `side` sets the sizes.
    private func dateBlock(side: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(date, format: .dateTime.weekday(.wide))
                .displayFont(side * 0.075, weight: .semibold)
                .foregroundStyle(palette.accent)
            Text(date, format: .dateTime.day())
                .displayFont(side * 0.42, weight: .bold)
                .foregroundStyle(palette.ink)
            Text(date, format: .dateTime.month(.wide).year())
                .displayFont(side * 0.06, weight: .semibold)
                .foregroundStyle(palette.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private func agenda(side: CGFloat) -> some View {
        let fontSize = side * 0.05
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Up Next")
                .font(.display(side * 0.06, weight: .bold))
                .foregroundStyle(palette.ink)
            if EventsList.hasAgenda(events, after: date) {
                EventsList(events: events, now: date, maxRows: 8, palette: palette, fontSize: fontSize)
            } else {
                EventsHint(palette: palette, fontSize: fontSize)
            }
        }
    }
}
