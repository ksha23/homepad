import HomePadCore
import HomePadUI
import SwiftUI

/// Settings > About: version, loaded modules, what they registered, and a
/// live event log for debugging.
struct AboutSettingsPane: View {
    @Environment(ModuleRegistry.self) private var registry
    @Environment(AppServices.self) private var services

    var body: some View {
        Form {
            Section("HomePad") {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Household", value: services.settings[CoreSettings.householdName])
                LabeledContent("Assistant", value: services.assistant.activeProviderName)
            }
            Section("Modules") {
                ForEach(registry.moduleIDs, id: \.self) { id in
                    Text(id).monospaced()
                }
            }
            Section("Registered") {
                LabeledContent("Apps", value: "\(registry.apps.count)")
                LabeledContent("Faces", value: "\(registry.faces.count)")
                LabeledContent("Widgets", value: "\(registry.widgets.count)")
                LabeledContent("Control Center tiles", value: "\(registry.controls.count)")
                LabeledContent("Settings panes", value: "\(registry.settingsPanes.count)")
                LabeledContent("Overlays", value: "\(registry.overlays.count)")
                LabeledContent("Assistant tools", value: "\(registry.tools.count)")
            }
            Section {
                EventLogView()
            } header: {
                Text("Event Log")
            } footer: {
                Text("The most recent events on HomePad's event bus, newest first.")
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// The event bus's recent events, refreshed as new ones arrive.
struct EventLogView: View {
    @Environment(AppServices.self) private var services
    @State private var entries: [(Date, HomePadEvent)] = []

    var body: some View {
        Group {
            if entries.isEmpty {
                Text("No events yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(entries.reversed().enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(entry.0, format: .dateTime.hour().minute().second())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(EventDescription.text(for: entry.1))
                        .monospaced()
                }
                .font(.footnote)
            }
        }
        .task {
            entries = services.events.recent
            for await _ in services.events.stream() {
                entries = services.events.recent
            }
        }
    }
}
