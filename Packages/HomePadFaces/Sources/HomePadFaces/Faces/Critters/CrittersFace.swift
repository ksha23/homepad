import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.critters`: Sprig, a little sprout creature, keeps you company
/// beside a giant date or time. Sprig sleeps at night, stretches in the
/// morning, reads in the evening, carries an umbrella in the rain, dresses
/// up for holidays and cheers when a timer finishes.
///
/// From across the room the date or time is as big as it gets. Up close it
/// glances smaller and a line with the date and the weather fades in under it.
struct CrittersFace: View {
    static let style = FaceOption.style([
        FaceChoice("date", "Date", systemImage: "calendar"),
        FaceChoice("time", "Time", systemImage: "clock"),
    ])
    /// Sprig's scenery and the big date or time take the text color. The face has no accent.
    static let color = FaceOption.color([.sand, .porcelain, .sage, .ocean, .rose, .graphite, .midnight], default: .sand,
                                        roles: .text)

    static let definition = FaceDefinition(
        id: "faces.critters", title: "Critters", summary: "Sprig reacts to the time, the weather, holidays and timers",
        systemImage: "leaf", sortOrder: 50, options: [style, color],
        widgets: .besideWidgets()
    ) { CrittersFace() }

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.faceAllowsMotion) private var allowsMotion
    @Environment(\.proximity) private var proximity
    @Environment(\.faceKeepClear) private var keepClear
    @Environment(AppServices.self) private var services
    @Environment(FacesRuntime.self) private var runtime
    @State private var isBlinking = false

    var body: some View {
        let isNightMode = condition == .night
        let palette = FacePalette(configuration.colors(Self.color))
        FaceTimeline(.minute) { date in
            let sky = skyCondition
            let timerDone = runtime.activity.happened(.timerFinished, within: 60, now: date)
            let look = CritterBrain.look(.init(date: date, sky: sky, temperatureFahrenheit: fahrenheit, timerJustFinished: timerDone))
            GeometryReader { proxy in
                // The scenery fills the face. Sprig and the date keep clear of the
                // widgets and the Now Playing pill.
                let area = proxy.size.leaving(keepClear)
                let side = min(area.width, area.height)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(palette.background).ignoresSafeArea()
                    // A new identity when motion stops or starts, so the scenery's and
                    // Sprig's repeating animations stop instead of running on unseen.
                    CritterScenery(look: look, sky: sky, isNight: look.pose == .sleeping, isAnimated: allowsMotion, ink: palette.ink)
                        .id(MotionID(look: look, isAnimated: allowsMotion))
                    character(date: date, look: look, timerDone: timerDone, palette: palette, side: side)
                        .frame(width: area.width, height: area.height)
                        .offset(x: keepClear.leading, y: keepClear.top)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .modifier(CritterNightTint(isOn: isNightMode))
            }
        }
        // The scenery sits on the background's color. At night it is drawn on black.
        .backdropTone(isNightMode ? .black : palette.tone)
        .task(id: allowsMotion) {
            guard allowsMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 3...6)))
                isBlinking = true
                try? await Task.sleep(for: .milliseconds(160))
                isBlinking = false
            }
        }
    }

    /// How much smaller the big date or time is up close.
    static let nearScale: CGFloat = 0.74

    /// The big date or time with Sprig beside it, laid out in the frame it
    /// gets: the face, or the part of it beside the widgets.
    private func character(date: Date, look: CritterLook, timerDone: Bool, palette: FacePalette, side: CGFloat) -> some View {
        GeometryReader { proxy in
            let isNear = proximity >= .mid
            let isTime = configuration.value(Self.style) == "time"
            let isPortrait = proxy.size.height > proxy.size.width
            ZStack {
                VStack(spacing: side * 0.01) {
                    Text(date, format: .dateTime.weekday(.wide))
                        .textCase(.uppercase)
                        .font(.display(side * 0.075, weight: .heavy))
                        .tracking(side * 0.004)
                    // One view at both distances. Its size animates.
                    Text(bigText(date))
                        .displayFont(side * (isTime ? 0.36 : 0.55) * (isNear ? Self.nearScale : 1), weight: .heavy)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    if isNear {
                        detailLine(date, isTime: isTime)
                            .font(.display(side * 0.04, weight: .semibold))
                            .transition(.proximityDetail)
                    }
                }
                .foregroundStyle(palette.ink)
                .offset(x: -side * 0.08)
                // Behind the Home Screen Sprig and the scenery stay, without words.
                .faceForeground()
                SprigView(look: look, isBlinking: isBlinking, isAnimated: allowsMotion)
                    .id(MotionID(look: look, isAnimated: allowsMotion))
                    .frame(width: side * (isPortrait ? 0.46 : 0.5), height: side * (isPortrait ? 0.46 : 0.5))
                    .position(x: proxy.size.width / 2 + side * (isPortrait ? 0.2 : 0.3),
                              y: proxy.size.height / 2 + side * (isPortrait ? 0.36 : 0.2))
                if timerDone, let label = runtime.activity.lastTimerLabel {
                    bubble("\(label) is done!", side: side, palette: palette)
                        .position(x: proxy.size.width / 2 + side * 0.18, y: proxy.size.height / 2 - side * 0.06)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The line under the big date or time up close: the rest of the date and
    /// the weather.
    private func detailLine(_ date: Date, isTime: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(date, format: isTime ? .dateTime.month(.wide).day() : .dateTime.month(.wide).year())
            if let weather = services.weather.current {
                Label("\(Int(weather.temperature.rounded()))°", systemImage: weather.symbolName)
            }
        }
        .lineLimit(1)
    }

    /// Identity for Sprig and the scenery: their look, and whether they move.
    private struct MotionID: Hashable {
        var look: CritterLook
        var isAnimated: Bool
    }

    private func bigText(_ date: Date) -> String {
        if configuration.value(Self.style) == "time" {
            return ClockText.parts(for: date, uses24Hour: ClockText.localeUses24Hour()).joined
        }
        return date.formatted(.dateTime.day())
    }

    private var skyCondition: SkyCondition? {
        if let override = FaceDebugOptions.weatherOverride { return SkyCondition.from(debugName: override) }
        return services.weather.current.map { SkyCondition.from(symbolName: $0.symbolName, conditionText: $0.conditionText) }
    }

    private var fahrenheit: Double? {
        guard let weather = services.weather.current else { return nil }
        return weather.unit == .fahrenheit ? weather.temperature : weather.temperature * 9 / 5 + 32
    }

    private func bubble(_ text: String, side: CGFloat, palette: FacePalette) -> some View {
        Text(text)
            .font(.display(side * 0.035, weight: .bold))
            // The bubble is white, so its text stays dark whatever the text color.
            .foregroundStyle(palette.inkOnWhite)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .background(Capsule().fill(.white))
            .flattenedShadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .faceForeground()
            .transition(.scale.combined(with: .opacity))
    }
}

/// Night mode for the Critters face: a dim red drawing on black, like
/// HomeView's red night Snoopy.
private struct CritterNightTint: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content
                .grayscale(1)
                .colorInvert()
                .colorMultiply(Theme.nightRed)
                .opacity(0.75)
                .background(Color.black.ignoresSafeArea())
        } else {
            content
        }
    }
}
