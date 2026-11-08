import HomePadCore
import HomePadUI
import SwiftUI

/// HomeView's header: two quiet lines in capitals at the left, the mini
/// widget (the glance unless the member changed it) right of them, then the
/// timer and Now Playing pills and the avatar that opens the People menu at
/// the right, all on one center line. The lines are the date over the time,
/// or "Good morning," over the name for a moment after someone is
/// recognized. Tapping them shows the face, like the clock on an iPad Lock
/// Screen.
///
/// The lines take the room they need first, then the pills and the avatar,
/// and the mini widget gets what is left between them (`MiniGlanceView` for
/// the glance), so it shrinks before anything else is cut off.
struct HomeScreenHeader: View {
    let member: HouseholdMember?
    /// The Home Screen's app icon size. The lines are sized from it, so they
    /// keep HomeView's proportion to the icons on every iPad.
    let iconSize: CGFloat
    /// The member's mini widget and its size, nil when they removed it.
    var miniWidget: MiniWidgetPlacement? = GlanceMiniWidget.headerDefault
    let onAvatar: () -> Void
    let onShowFace: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(ShellNavigator.self) private var navigator
    /// Who the greeting is for while it shows.
    @State private var greetedName: String?

    /// How long "Good morning," shows after someone is recognized, before the
    /// date and time come back.
    static let greetingDuration: Duration = .seconds(8)

    /// The lines' point size: about a quarter of an app icon, as on HomeView,
    /// a little larger than the icons' labels.
    static func textSize(iconSize: CGFloat) -> CGFloat {
        (iconSize * 0.24).rounded()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            TimelineView(.everyMinute) { context in
                let lines = greetedName.map { HomeHeaderLines.greeting(context.date, name: $0) } ?? .date(context.date)
                HeaderLinesView(lines: lines, size: Self.textSize(iconSize: iconSize))
                    // The greeting and the date crossfade. Once a minute the time rolls over.
                    .animation(Theme.Motion.standard, value: lines)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onShowFace)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Shows the face")
            }
            .layoutPriority(1)
            // The mini widget at the lowest priority, so it is offered only what the lines, pills and avatar leave,
            // and stretched across that room so the pills and avatar stay at the trailing edge.
            Group {
                if let miniWidget, let widget = registry.miniWidget(miniWidget.widgetID) {
                    // Set off from the lines by more than its own items are from each other, so it
                    // reads as a block of its own rather than more of the date.
                    widget.makeView(MiniWidgetContext(
                        size: widget.shownSize(miniWidget.size), surface: .wallpaper,
                        textSize: Self.textSize(iconSize: iconSize), leadingGap: Theme.Spacing.xl - Theme.Spacing.m,
                        openApp: { navigator.open(appID: $0) }
                    ))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            HStack(spacing: Theme.Spacing.m) {
                // Here instead of floating over the screen, so they never cover the
                // date: large when there is room, compact when there is less.
                ViewThatFits(in: .horizontal) {
                    TopPills(isCompact: false)
                    TopPills(isCompact: true)
                    Color.clear.frame(width: 0, height: 0)
                }
                Button(action: onAvatar) {
                    // A turning ring while face recognition starts after launch.
                    AvatarView(member: member, size: Theme.Size.profileButton)
                        .startingRing(services.presence.isRecognitionStarting)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("People, \(member?.name ?? "Guest")"
                    + (services.presence.isRecognitionStarting ? ", face recognition is starting" : ""))
            }
        }
        // The avatar sets the row's height, so it sits `profileButtonInset` from the
        // top as from the side, where a face draws it too.
        .frame(minHeight: Theme.Size.profileButton)
        .padding(.horizontal, Theme.Spacing.l)
        .task(id: member?.id) {
            guard let name = member?.name, !name.isEmpty else {
                greetedName = nil
                return
            }
            greetedName = name
            try? await Task.sleep(for: Self.greetingDuration)
            guard !Task.isCancelled else { return }
            greetedName = nil
        }
    }
}

/// The header's two lines in SF Pro capitals: regular over semibold.
private struct HeaderLinesView: View {
    let lines: HomeHeaderLines
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 0) {
                Text(lines.top)
                    .font(.system(size: size, weight: .regular))
                Text(lines.bottom)
                    .font(.system(size: size, weight: .semibold))
                    .contentTransition(.numericText())
            }
            .id(lines.isGreeting)
            .transition(.opacity)
        }
        .textCase(.uppercase)
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // The icons' labels' soft shadow, for a bright wallpaper.
        .wallpaperLabelShadow()
    }
}
