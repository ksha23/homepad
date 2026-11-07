import HomePadCore
import HomePadUI
import SwiftUI

/// Connect Home Assistant: instances found on the network, a manual URL, the
/// long-lived access token, a connection test and the live status.
struct HomeAssistantSettingsSection: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @State private var discovery = HomeAssistantDiscovery()
    @State private var urlText = ""
    @State private var token = ""
    @State private var testResult: Result<String, Error>?
    @State private var isTesting = false

    private var backend: HomeAssistantBackend { service.homeAssistant }

    var body: some View {
        Section {
            LabeledContent("Status") {
                Text(backend.status.summary)
                    .foregroundStyle(backend.status.isConnected ? .green : .secondary)
            }
            if !discovery.instances.isEmpty {
                ForEach(discovery.instances) { instance in
                    Button {
                        urlText = instance.url.absoluteString
                    } label: {
                        LabeledContent {
                            Text(instance.url.host() ?? "")
                        } label: {
                            Label(instance.name, systemImage: "house.badge.wifi.fill")
                        }
                    }
                }
            } else if discovery.isSearching {
                LabeledContent("Looking on your network") { ProgressView() }
            }
            TextField(text: $urlText, prompt: Text(verbatim: "http://homeassistant.local:8123")) { Text("Address") }
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(text: $token, prompt: Text("Long-lived access token")) { Text("Token") }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let testResult {
                switch testResult {
                case .success(let message): Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failure(let error): Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            Button(isTesting ? "Testing" : "Test Connection", systemImage: "network", action: test)
                .disabled(draft == nil || isTesting)
            Button("Save and Connect", systemImage: "link") { backend.configure(draft) }
                .disabled(draft == nil)
            if backend.isConfigured {
                Button("Disconnect Home Assistant", systemImage: "link.badge.minus", role: .destructive) {
                    backend.configure(nil)
                    token = ""
                }
            }
        } header: {
            Text("Home Assistant")
        } footer: {
            Text("Create a long-lived access token in Home Assistant under your profile, Security. The token stays in the iPad's keychain.")
        }
        .onAppear {
            urlText = backend.configuration?.baseURL.absoluteString ?? urlText
            discovery.start()
        }
        .onDisappear { discovery.stop() }
    }

    /// The typed URL and token, or the saved token when only the URL changed.
    private var draft: HomeAssistantConfiguration? {
        guard let url = HomeAssistantConfiguration.normalizedURL(from: urlText) else { return nil }
        let typed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let usable = typed.isEmpty ? backend.configuration?.token : typed else { return nil }
        return HomeAssistantConfiguration(baseURL: url, token: usable)
    }

    private func test() {
        guard let draft else { return }
        isTesting = true
        Task {
            do {
                testResult = .success(try await HomeAssistantConnectionTest.run(draft))
            } catch {
                testResult = .failure(error)
            }
            isTesting = false
        }
    }
}
