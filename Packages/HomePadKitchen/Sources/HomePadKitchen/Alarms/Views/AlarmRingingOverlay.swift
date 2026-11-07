import HomePadCore
import HomePadUI
import SwiftUI

/// Full-screen alert while an alarm rings: the time, whose alarm and its
/// label, Snooze and Stop, and bells on a loop. Shows over everything,
/// including faces, the sleeping screen and night mode. Anyone in the room may
/// snooze or stop it, since it rings for everyone.
struct AlarmRingingOverlay: View {
    let service: AlarmService
    let chime: ChimePlayer
    @Environment(AppServices.self) private var services

    /// Bells carry through a bedroom door better than the kitchen chimes.
    static let sound: ChimeSound = .bells

    var body: some View {
        let ringing = service.ringingAlarms
        ZStack {
            if let alarm = ringing.first {
                alert(for: alarm, others: ringing.count - 1)
                    .transition(.fullScreenSurface(scale: 1.04))
            }
        }
        .animation(Theme.Motion.screen, value: ringing.map(\.id))
        .onChange(of: !ringing.isEmpty, initial: true) { _, isRinging in
            if isRinging {
                chime.ring(Self.sound, audioSession: services.audioSession)
            } else {
                chime.stop()
            }
        }
    }

    private func alert(for alarm: HomeAlarm, others: Int) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.s) {
                    Label(heading(for: alarm), systemImage: "alarm.fill")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    TimelineView(.everyMinute) { context in
                        Text(context.date.clockTime())
                            .font(.display(180))
                            .contentTransition(.numericText())
                    }
                }
                HStack(spacing: Theme.Spacing.l) {
                    if alarm.allowsSnooze {
                        GlassCapsuleButton("Snooze", systemImage: "zzz", size: .extraLarge) { service.snooze(alarm.id) }
                    }
                    GlassCapsuleButton("Stop", systemImage: "stop.fill", size: .extraLarge, isProminent: true, tint: .orange) {
                        service.stop(alarm.id)
                    }
                }
                if others > 0 {
                    GlassCapsuleButton("Stop All \(others + 1) Alarms") {
                        service.ringingAlarms.forEach { service.stop($0.id) }
                    }
                }
            }
            .padding(Theme.Spacing.xl)
            .fullScreenSurfaceContent()
        }
        // A dark alert in every appearance, like the Clock app's, so a bedroom
        // is not lit up white when it rings.
        .environment(\.colorScheme, .dark)
        .nightModeAware()
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// "Alex · Wake Up", or the label alone when its owner is gone.
    private func heading(for alarm: HomeAlarm) -> String {
        let owner = services.household.members.first { $0.id == alarm.ownerID }?.name
        return [owner, alarm.title].compactMap { $0 }.joined(separator: " · ")
    }
}
