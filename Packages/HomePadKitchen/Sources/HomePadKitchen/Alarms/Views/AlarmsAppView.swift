import HomePadCore
import HomePadUI
import SwiftUI

/// The Alarms app: the recognized person's alarms as a list, like the Clock
/// app's Alarms on iPad, with the next one and how far away it is on top. Tap
/// an alarm to change it, its switch to turn it on or off, and Add Alarm for a
/// new one. The shell opens it only for a recognized member.
struct AlarmsAppView: View {
    @Environment(AlarmService.self) private var service
    @Environment(AppServices.self) private var services
    @State private var editing: AlarmDraft?

    var body: some View {
        AppScreen("Alarms", accessory: {
            if owner != nil {
                GlassIconButton("plus", label: "Add Alarm", isProminent: true) { addAlarm() }
            }
        }) {
            if let owner {
                let alarms = service.alarms(ownedBy: owner)
                if alarms.isEmpty {
                    EmptyStateView("No Alarms",
                                   message: "Set an alarm to wake up to. Only you see your alarms here, and they ring for everyone in the room.",
                                   systemImage: "alarm", actionTitle: "Add Alarm", action: addAlarm)
                } else {
                    list(alarms, owner: owner)
                }
            } else {
                EmptyStateView("Alarms Are Personal",
                               message: "Look at the screen so HomePad recognizes you, and your alarms show here.",
                               systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .sheet(item: $editing) { draft in
            AlarmEditorSheet(draft: draft)
                .environment(service)
        }
        .nightModeAware()
        #if DEBUG
        .task {
            // After the demo alarms are in place.
            try? await Task.sleep(for: .seconds(1))
            if let draft = AlarmDebugLaunch.editorDraft(service: service, owner: owner) { editing = draft }
        }
        #endif
    }

    /// Whose alarms show: the member recognized at the screen.
    private var owner: UUID? {
        services.household.isPersonalContentUnlocked ? services.household.activeMember?.id : nil
    }

    private func list(_ alarms: [HomeAlarm], owner: UUID) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NextAlarmSummary(owner: owner)
                    .padding(.bottom, Theme.Spacing.m)
                ForEach(alarms) { alarm in
                    Divider()
                    AlarmRow(alarm: alarm) { editing = AlarmDraft(alarm: alarm, isNew: false) }
                }
                Divider()
            }
            .padding(.bottom, Theme.Spacing.xl)
            .animation(Theme.Motion.standard, value: alarms)
        }
        .scrollIndicators(.hidden)
    }

    private func addAlarm() {
        guard let owner else { return }
        editing = AlarmDraft(alarm: HomeAlarm(ownerID: owner, hour: 7, minute: 0), isNew: true)
    }
}

/// An alarm being added or changed in the editor sheet.
struct AlarmDraft: Identifiable {
    var alarm: HomeAlarm
    let isNew: Bool
    var id: UUID { alarm.id }
}

/// "Next alarm tomorrow at 6:30 AM, in 9 hr 14 min", redrawn once a minute.
private struct NextAlarmSummary: View {
    let owner: UUID
    @Environment(AlarmService.self) private var service

    var body: some View {
        TimelineView(.everyMinute) { context in
            Group {
                if let next = service.nextRing(ownedBy: owner) {
                    let lead = service.isSnoozed(next.alarm.id) ? "Snoozed until" : "Next alarm"
                    Text("\(lead) \(AlarmFormat.when(next.date, from: context.date)), \(AlarmFormat.countdown(to: next.date, from: context.date))")
                } else {
                    Text("All alarms are off")
                }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }
}
