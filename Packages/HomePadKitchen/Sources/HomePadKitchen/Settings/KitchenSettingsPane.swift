import HomePadCore
import HomePadUI
import SwiftUI

/// Settings > Kitchen. Curated choices only: a timer sound from a short list,
/// presets picked from a catalog, default servings and units.
struct KitchenSettingsPane: View {
    let context: KitchenContext
    let alarms: any TimerAlarmScheduling
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    @State private var supporterKey = ""

    var body: some View {
        let settings = services.settings
        form(settings)
            .onAppear { supporterKey = services.keychain.string(for: KitchenSecrets.mealDBKey) ?? "" }
            .onDisappear(perform: saveSupporterKey)
    }

    private func saveSupporterKey() {
        let trimmed = supporterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (services.keychain.string(for: KitchenSecrets.mealDBKey) ?? "") else { return }
        services.keychain.set(trimmed.isEmpty ? nil : trimmed, for: KitchenSecrets.mealDBKey)
        Task { await context.discovery.refresh() }
    }

    private func form(_ settings: SettingsStore) -> some View {
        Form {
            Section {
                Picker("Sound", selection: settings.binding(KitchenSettings.chime)) {
                    ForEach(ChimeSound.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings[KitchenSettings.chime]) { _, sound in
                    context.chime.preview(sound, audioSession: services.audioSession)
                }
                Picker("Ranged Times Start At", selection: settings.binding(KitchenSettings.rangedTime)) {
                    ForEach(RangedTimeChoice.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Timers")
            } footer: {
                Text("A step that says \"3 to 5 minutes\" starts a timer for the shortest or the longest time.")
            }

            Section {
                ForEach(TimerPreset.catalog) { preset in
                    presetRow(preset)
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("Choose up to \(KitchenSettings.maxPresets). They appear in Timers and Control Center.")
            }

            Section {
                Picker("Default Servings", selection: settings.binding(KitchenSettings.defaultServings)) {
                    Text("As Written").tag(0)
                    ForEach(KitchenSettings.servingChoices, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Units", selection: settings.binding(KitchenSettings.unitSystem)) {
                    ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                }
                Button("Restore Sample Recipes") { context.library.restoreSamples() }
            } header: {
                Text("Recipes")
            }

            Section {
                SecureField("Supporter Key (Optional)", text: $supporterKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(saveSupporterKey)
            } header: {
                Text("Recipe Search")
            } footer: {
                Text("Search, Discover and the starter recipes come from \(context.catalog.name) with its free key. A supporter key from \(context.catalog.name) brings ten new ideas at a time. The key stays in the iPad's keychain.")
            }

            Section {
                Toggle("Ring in the Background", isOn: settings.binding(KitchenSettings.backgroundAlarms))
                alarmStatus
                Toggle("Live Activities", isOn: settings.binding(KitchenSettings.liveActivities))
            } header: {
                Text("Alerts")
            } footer: {
                Text("Timers and wake-up alarms use system alarms so they ring even when another app is open or the screen is locked.")
            }
        }
    }

    private func presetRow(_ preset: TimerPreset) -> some View {
        let selected = services.settings[KitchenSettings.presets]
        let isOn = selected.contains(preset)
        return Button {
            var updated = selected
            if isOn {
                updated.removeAll { $0 == preset }
            } else if updated.count < KitchenSettings.maxPresets {
                updated.append(preset)
            }
            services.settings[KitchenSettings.presets] = updated.sorted { $0.seconds < $1.seconds }
        } label: {
            HStack {
                Text(preset.title).foregroundStyle(.primary)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(.orange) }
            }
        }
        .disabled(!isOn && selected.count >= KitchenSettings.maxPresets)
    }

    @ViewBuilder
    private var alarmStatus: some View {
        switch alarms.authorization {
        case .authorized:
            LabeledContent("Alarms", value: "Allowed")
        case .notDetermined:
            Button("Allow Alarms") { Task { await alarms.requestAuthorization() } }
        case .denied:
            Button("Allow Alarms in Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .unavailable:
            LabeledContent("Alarms", value: "Not Available")
        }
    }
}
