import HomePadCore
import HomePadUI
import SwiftUI

/// Which Home Assistant dashboard view the Dashboards app opens, and the curated web panels.
struct DashboardSettingsSection: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(AppServices.self) private var services
    @State private var options: [DashboardOption] = []
    @State private var editingPanel: WebPanel?

    private var settings: Binding<DashboardSettings> { services.settings.binding(SmartHomeSettings.dashboards) }

    var body: some View {
        Section {
            if service.homeAssistant.isConfigured {
                Picker("Home Assistant View", selection: settings.dashboardPath) {
                    ForEach(choices) { Text($0.title).tag($0.path) }
                }
            }
            // Each row presents its own editor. A section hands its modifiers
            // to every row, and several sheets on one binding present none.
            ForEach(settings.wrappedValue.panels) { panel in
                Button {
                    editingPanel = panel
                } label: {
                    LabeledContent {
                        Text(panel.resolvedURL?.host() ?? panel.url)
                    } label: {
                        Label(panel.name, systemImage: panel.symbol.rawValue).foregroundStyle(.primary)
                    }
                }
                .sheet(item: editing { $0.id == panel.id }) { editor($0) }
            }
            .onDelete { settings.wrappedValue.panels.remove(atOffsets: $0) }
            Button("Add Web Panel", systemImage: "plus.rectangle.on.rectangle") {
                editingPanel = WebPanel(name: "", symbol: .video, url: "")
            }
            .sheet(item: editing { new in !settings.wrappedValue.panels.contains { $0.id == new.id } }) { editor($0) }
        } header: {
            Text("Dashboards")
        } footer: {
            Text("The Dashboards app shows your Home Assistant dashboard and panels such as Frigate or Grafana in HomePad's style.")
        }
        .task(id: service.homeAssistant.status) {
            guard service.homeAssistant.status.isConnected, let connection = service.homeAssistant.connection else { return }
            options = await HADashboardCatalog.load(from: connection)
        }
    }

    /// The panel being edited, for the row whose panel it is.
    private func editing(where matches: @escaping (WebPanel) -> Bool) -> Binding<WebPanel?> {
        Binding(get: { editingPanel.flatMap { matches($0) ? $0 : nil } }, set: { editingPanel = $0 })
    }

    private func editor(_ panel: WebPanel) -> some View {
        WebPanelEditor(panel: panel) { saved in
            // First, so a new panel's own row does not open it again.
            editingPanel = nil
            var panels = settings.wrappedValue.panels
            if let index = panels.firstIndex(where: { $0.id == saved.id }) { panels[index] = saved } else { panels.append(saved) }
            settings.wrappedValue.panels = panels
        }
    }

    /// Loaded views, keeping the current path even before the list arrives.
    private var choices: [DashboardOption] {
        let current = settings.wrappedValue.dashboardPath
        return options.contains { $0.path == current } ? options : [DashboardOption(title: current, path: current)] + options
    }
}
