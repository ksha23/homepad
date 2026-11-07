import HomePadCore
import HomePadUI
import SwiftUI

/// The Dashboards app, an advanced view next to the native Home app: the person's
/// Home Assistant dashboard (all their cards, WebRTC cameras and more-info dialogs)
/// and a few curated web panels, each inside HomePad chrome and theme.
///
/// It reopens on the page it was left on. A Home Assistant page asked for by
/// another screen wins, for that visit.
struct DashboardsAppView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(DashboardNavigator.self) private var navigator
    @Environment(AppServices.self) private var services
    /// A local page standing in for Home Assistant (debug launch argument for screenshots).
    var fixtureURL: URL?

    @AppState(SmartHomeAppState.dashboard) private var selection
    @State private var requestedPath: String?

    private var settings: DashboardSettings { services.settings[SmartHomeSettings.dashboards] }

    var body: some View {
        AppScreen("Dashboards", titleAccessory: { pagePicker }) {
            if homeAssistantPage == nil && settings.panels.isEmpty {
                EmptyStateView("No Dashboards", message: "Connect Home Assistant or add a web panel in Settings, Smart Home.",
                               systemImage: "rectangle.3.group")
            } else if let page = currentPage {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                DashboardWebView(page: page, accent: Theme.tint(for: .thermostat))
                    .id(page)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.primary.opacity(0.12), lineWidth: 1))
            }
        }
        .onAppear(perform: takeRequest)
        .onChange(of: navigator.requestedPath) { takeRequest() }
    }

    private func takeRequest() {
        if let path = navigator.takeRequestedPath() {
            requestedPath = path
            selection = .homeAssistant
        }
    }

    /// One page the Dashboards app can show.
    private struct Choice {
        var selection: DashboardSelection
        var title: String
        var symbol: String
    }

    /// Home Assistant when it is set up, then each web panel.
    private var choices: [Choice] {
        let homeAssistant = homeAssistantPage == nil ? [] : [Choice(selection: .homeAssistant, title: "Home Assistant", symbol: "house.fill")]
        return homeAssistant + settings.panels.map { Choice(selection: .panel($0.id), title: $0.name, symbol: $0.symbol.rawValue) }
    }

    /// The page on screen, beside the title as every app's view picker is.
    @ViewBuilder
    private var pagePicker: some View {
        let choices = choices
        if choices.count > 1, let shown = choices.first(where: { $0.selection == selection }) ?? choices.first {
            HeaderPicker("Dashboard", selection: $selection, title: shown.title, systemImage: shown.symbol) {
                ForEach(choices, id: \.selection) { choice in
                    Label(choice.title, systemImage: choice.symbol).tag(choice.selection)
                }
            }
        }
    }

    /// The chosen page, or the first one when the choice is gone (Home Assistant
    /// signed out, a panel deleted), as the picker shows.
    private var currentPage: DashboardPage? {
        switch selection {
        case .panel(let id):
            if let panel = settings.panels.first(where: { $0.id == id }) { return panelPage(panel) }
        case .homeAssistant:
            break
        }
        return homeAssistantPage ?? settings.panels.first.flatMap(panelPage)
    }

    private func panelPage(_ panel: WebPanel) -> DashboardPage? {
        panel.resolvedURL.map { DashboardPage(url: $0, homeAssistantToken: nil) }
    }

    /// The configured dashboard path (or a requested one) with `external_auth=1`.
    private var homeAssistantPage: DashboardPage? {
        if let fixtureURL { return DashboardPage(url: fixtureURL, homeAssistantToken: "fixture") }
        guard let configuration = service.homeAssistant.configuration else { return nil }
        let path = requestedPath ?? settings.dashboardPath
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false),
              let target = URLComponents(string: path.hasPrefix("/") ? path : "/" + path) else { return nil }
        components.path = target.path
        components.queryItems = (target.queryItems ?? []) + [URLQueryItem(name: "external_auth", value: "1")]
        return components.url.map { DashboardPage(url: $0, homeAssistantToken: configuration.token) }
    }
}
