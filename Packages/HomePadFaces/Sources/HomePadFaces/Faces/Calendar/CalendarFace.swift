import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.calendar`: this month as a grid with today circled and its number
/// drawn large behind the grid. From across the room the month fills the
/// face. Up close it makes room for today's events, a recognized member's
/// own or the shared household calendars'. The Up Next style shows the date
/// in big type instead, with today's events beside it up close.
///
/// The grid lays out again at each distance. Its type sizes animate
/// (`displayFont`), so it glides between the two instead of stepping.
struct CalendarFace: View {
    static let style = FaceOption.style([
        FaceChoice("month", "Month", systemImage: "calendar"),
        FaceChoice("upNext", "Up Next", systemImage: "list.bullet.rectangle"),
    ])
    static let color = FaceOption.color([.porcelain, .sand, .ocean, .lavender, .sage, .graphite], default: .porcelain)

    static let definition = FaceDefinition(
        id: "faces.calendar", title: "Calendar", summary: "The month at a glance with today's events",
        systemImage: "calendar", sortOrder: 21, options: [style, color],
        widgets: .besideWidgets()
    ) { CalendarFace() }

    @Environment(\.faceInsets) private var faceInsets
    @Environment(\.faceKeepClear) private var keepClear

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity
    @Environment(\.facesShowPersonal) private var showPersonal
    @Environment(AppServices.self) private var services
    @State private var events = TodayEvents()

    var body: some View {
        let palette = FacePalette.resolve(configuration.colors(Self.color), condition: condition)
        let isUpNext = configuration.value(Self.style) == "upNext"
        FaceTimeline(.minute) { date in
            if isUpNext {
                CalendarUpNext(date: date, events: events.visible(showPersonal: showPersonal), palette: palette,
                               isNear: proximity >= .mid)
            } else {
                month(date: date, palette: palette)
            }
        }
        .task(id: "\(showPersonal)|\(services.calendar.reloadKey)") {
            while !Task.isCancelled {
                await events.refresh(calendar: services.calendar)
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
        .faceBackdrop(tone: palette.tone) { palette.background.ignoresSafeArea() }
        .faceIsLoading(!events.hasLoaded)
    }

    /// The month grid, with today's events beside or under it up close.
    private func month(date: Date, palette: FacePalette) -> some View {
        GeometryReader { proxy in
            // Clear of the widgets and the Now Playing pill.
            let area = proxy.size.leaving(keepClear)
            let isPortrait = proxy.size.height > proxy.size.width
            let visible = events.visible(showPersonal: showPersonal)
            let layout = isPortrait ? AnyLayout(VStackLayout(spacing: Theme.Spacing.xl)) : AnyLayout(HStackLayout(spacing: Theme.Spacing.xl))
            ZStack {
                Rectangle().fill(palette.background).ignoresSafeArea()
                layout {
                    MonthGridView(grid: .make(for: date), date: date, palette: palette)
                    if proximity >= .mid {
                        let side = min(area.width, area.height)
                        let height = isPortrait ? area.height * 0.3 : area.height - Theme.Spacing.xl * 2.8
                        eventsPanel(visible, date: date, palette: palette, side: side, height: height)
                            .frame(maxWidth: isPortrait ? .infinity : area.width * 0.34,
                                   maxHeight: height, alignment: .topLeading)
                            .transition(.proximityDetail)
                    }
                }
                .padding(faceInsets)
            }
        }
    }

    /// "Today" over as many events as fit the panel's height.
    private func eventsPanel(_ visible: [CalendarItem], date: Date, palette: FacePalette, side: CGFloat, height: CGFloat) -> some View {
        let title = side * 0.05
        let fontSize = side * 0.034
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Today")
                .font(.display(title, weight: .bold))
                .foregroundStyle(palette.ink)
            EventsList(events: visible, now: date, maxRows: 12, palette: palette, fontSize: fontSize)
        }
    }
}

/// The month grid with the big day numeral behind it. The weekdays and days
/// are bold in the accent, like HomeView's. Where they cross the big day,
/// which is the accent too, they turn the background's color, so they read
/// on it.
private struct MonthGridView: View {
    let grid: MonthGrid
    let date: Date
    let palette: FacePalette

    var body: some View {
        GeometryReader { proxy in
            let cellWidth = proxy.size.width / 7
            let headerHeight = proxy.size.height * 0.16
            let cellHeight = (proxy.size.height - headerHeight) / CGFloat(MonthGrid.weeks + 1)
            let font = min(cellWidth, cellHeight) * 0.46
            let big = bigDay(size: proxy.size, headerHeight: headerHeight)
            ZStack(alignment: .topLeading) {
                big
                VStack(spacing: 0) {
                    HStack {
                        Text(grid.month, format: .dateTime.month(.wide).year())
                        Spacer()
                        Text(date, format: .dateTime.hour().minute())
                    }
                    // As wide as the grid allows too, so the month is never cut off
                    // beside the face's widgets.
                    .displayFont(min(headerHeight * 0.42, proxy.size.width / 11), weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(palette.accent)
                    .frame(height: headerHeight, alignment: .top)
                    days(cellWidth: cellWidth, cellHeight: cellHeight, font: font, ink: palette.accent)
                }
                // At night the big day is dim enough for red days to read on it.
                if !palette.isNight {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: headerHeight)
                        days(cellWidth: cellWidth, cellHeight: cellHeight, font: font, ink: palette.top)
                    }
                    .mask(alignment: .topLeading) { big }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    /// Today's number as tall as the grid, or as wide for two digits. Sized
    /// here rather than by `minimumScaleFactor`, so its size animates.
    private func bigDay(size: CGSize, headerHeight: CGFloat) -> some View {
        Text(date, format: .dateTime.day())
            .displayFont(min(size.height - headerHeight, size.width * 0.8), weight: .heavy)
            .foregroundStyle(palette.accent.opacity(palette.isNight ? 0.25 : 0.85))
            .minimumScaleFactor(0.3)
            .lineLimit(1)
            .frame(width: size.width, height: size.height - headerHeight)
            .offset(y: headerHeight)
    }

    /// The weekday letters and the weeks, in `ink`. Days of the months
    /// before and after are fainter.
    private func days(cellWidth: CGFloat, cellHeight: CGFloat, font: CGFloat, ink: Color) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(grid.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).frame(width: cellWidth, height: cellHeight)
                }
            }
            .displayFont(font * 0.85, weight: .bold)
            .foregroundStyle(ink)
            ForEach(0..<MonthGrid.weeks, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(grid.days[(week * 7)..<(week * 7 + 7)]) { day in
                        dayCell(day, font: font, ink: ink)
                            .frame(width: cellWidth, height: cellHeight)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: MonthGrid.Day, font: CGFloat, ink: Color) -> some View {
        let text = Text("\(day.number)").monospacedDigit().displayFont(font, weight: .bold)
        if day.isToday {
            text
                .foregroundStyle(palette.isNight ? Color.black : palette.top)
                .frame(width: font * 1.9, height: font * 1.9)
                .background(Circle().fill(palette.ink))
        } else {
            text.foregroundStyle(day.isInMonth ? ink : ink.opacity(0.45))
        }
    }
}
