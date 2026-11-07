import HomePadCore
import HomePadUI
import SwiftUI

/// Edits the Smart Rotation rules as a grouped list, like iOS Settings.
/// Rules are checked top to bottom. Drag to reorder, swipe to delete.
struct RotationRulesEditor: View {
    @Environment(FacesRuntime.self) private var runtime
    @Environment(ModuleRegistry.self) private var registry

    var body: some View {
        let store = runtime.rotation
        let settings = Binding(get: { store.current }, set: { store.current = $0 })
        Form {
            Section {
                ForEach(settings.rules) { $rule in
                    RotationRuleRow(rule: $rule, faces: choosableFaces)
                }
                .onDelete { settings.wrappedValue.rules.remove(atOffsets: $0) }
                .onMove { settings.wrappedValue.rules.move(fromOffsets: $0, toOffset: $1) }
                addRuleMenu(settings)
            } header: {
                Text("Rules")
            } footer: {
                Text("The first rule that applies picks the face. Drag to change the order.")
            }
            Section {
                FacePickerRow(title: "Otherwise Show", selection: settings.fallbackFaceID, faces: choosableFaces)
            }
            Section {
                Button("Restore Default Rules", role: .destructive) { store.restoreDefaults() }
            }
        }
        .environment(\.editMode, .constant(.active))
    }

    private var choosableFaces: [FaceDescriptor] {
        registry.faces.filter { $0.id != RotationEngine.selfID }
    }

    private func addRuleMenu(_ settings: Binding<RotationSettings>) -> some View {
        Menu {
            ForEach(Self.templates, id: \.title) { template in
                Button {
                    settings.wrappedValue.rules.append(RotationRule(trigger: template.trigger, faceID: template.faceID))
                } label: {
                    Label(template.title, systemImage: template.trigger.systemImage)
                }
            }
        } label: {
            Label("Add Rule", systemImage: "plus.circle.fill")
        }
    }

    private static let templates: [(title: String, trigger: RotationTrigger, faceID: String)] = [
        ("Night Mode", .night, "faces.night"),
        ("Time of Day", .timeOfDay(startMinute: 18 * 60, endMinute: 22 * 60), "faces.photos"),
        ("Doorbell Rings", .activity(.doorbell, withinSeconds: 120), "faces.cameras"),
        ("Motion Detected", .activity(.motion, withinSeconds: 300), "faces.flow"),
        ("Timer Finishes", .activity(.timerFinished, withinSeconds: 60), "faces.critters"),
        ("Recognized Person", .memberFace, ""),
    ]
}

/// One rule: its trigger (with inline controls for times and windows) and its face.
/// The rule stays one row so it can be dragged, and each of its controls gets a
/// line `Theme.Size.tapTarget` tall, like a row of its own, so a finger at arm's
/// length never catches the control above or below.
private struct RotationRuleRow: View {
    @Binding var rule: RotationRule
    let faces: [FaceDescriptor]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $rule.isEnabled) {
                Label(rule.trigger.title, systemImage: rule.trigger.systemImage)
            }
            .frame(minHeight: Theme.Size.tapTarget)
            triggerControls
            if rule.trigger != .memberFace {
                FacePickerRow(title: "Show", selection: $rule.faceID, faces: faces)
                    .frame(minHeight: Theme.Size.tapTarget)
            } else {
                Text("Shows the face that person chose for themselves.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Theme.Spacing.s)
            }
        }
    }

    @ViewBuilder
    private var triggerControls: some View {
        switch rule.trigger {
        case .timeOfDay(let start, let end):
            HStack(spacing: Theme.Spacing.l) {
                DatePicker("From", selection: minuteBinding(start) { rule.trigger = .timeOfDay(startMinute: $0, endMinute: end) },
                           displayedComponents: .hourAndMinute)
                DatePicker("To", selection: minuteBinding(end) { rule.trigger = .timeOfDay(startMinute: start, endMinute: $0) },
                           displayedComponents: .hourAndMinute)
            }
            .frame(minHeight: Theme.Size.tapTarget)
        case .activity(let activity, let seconds):
            Stepper("For \(Int(seconds / 60)) min", value: Binding(
                get: { seconds / 60 },
                set: { rule.trigger = .activity(activity, withinSeconds: $0 * 60) }
            ), in: 1...30)
            .frame(minHeight: Theme.Size.tapTarget)
        case .night, .memberFace:
            EmptyView()
        }
    }

    private func minuteBinding(_ minutes: Int, set: @escaping (Int) -> Void) -> Binding<Date> {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        return Binding(
            get: { midnight.addingTimeInterval(TimeInterval(minutes * 60)) },
            set: { set(RotationEngine.minuteOfDay($0, calendar: calendar)) }
        )
    }
}

/// A menu picker listing registered faces by title.
struct FacePickerRow: View {
    let title: String
    @Binding var selection: String
    let faces: [FaceDescriptor]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(faces) { face in
                Label(face.title, systemImage: face.systemImage).tag(face.id)
            }
        }
        .pickerStyle(.menu)
    }
}
