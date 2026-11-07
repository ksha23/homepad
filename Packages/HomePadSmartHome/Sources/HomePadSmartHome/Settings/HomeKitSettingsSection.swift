import HomePadCore
import HomePadUI
import SwiftUI

/// Connect Apple Home: a friendly explanation before the system prompt, the home
/// picker, and Apple's own accessory setup sheet.
struct HomeKitSettingsSection: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(\.openURL) private var openURL
    @State private var setupError: String?

    private var homeKit: HomeKitBackend { service.homeKit }

    var body: some View {
        Section {
            LabeledContent("Status") {
                Text(homeKit.status.summary).foregroundStyle(.secondary)
            }
            switch homeKit.access {
            case .notRequested:
                Button("Connect Apple Home", systemImage: "house.fill") { homeKit.connect() }
            case .waiting:
                LabeledContent("Waiting for permission") { ProgressView() }
            case .denied, .restricted:
                Button("Open iPad Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .authorized:
                authorizedRows
            }
        } header: {
            Text("Apple Home")
        } footer: {
            Text(footer)
        }
        .alert("Accessory Setup", isPresented: Binding(get: { setupError != nil }, set: { if !$0 { setupError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(setupError ?? "")
        }
    }

    @ViewBuilder
    private var authorizedRows: some View {
        if homeKit.homes.isEmpty {
            Text("No homes yet. Set up a home in the Home app, then it appears here.")
                .foregroundStyle(.secondary)
        } else {
            Picker("Home", selection: Binding(
                get: { homeKit.homes.first { $0.name == homeKit.selectedHomeName }?.id ?? homeKit.homes[0].id },
                set: { homeKit.selectHome($0) }
            )) {
                ForEach(homeKit.homes) { Text($0.name).tag($0.id) }
            }
            Button("Add Accessory", systemImage: "plus.circle") {
                Task {
                    do { try await homeKit.addAccessory() } catch { setupError = error.localizedDescription }
                }
            }
        }
        Button("Open the Home App", systemImage: "arrow.up.forward.app") {
            if let url = URL(string: "com.apple.home://") { openURL(url) }
        }
        Button("Stop Using Apple Home", systemImage: "house.slash", role: .destructive) { homeKit.disconnect() }
    }

    private var footer: String {
        switch homeKit.access {
        case .notRequested:
            "HomePad asks for permission to show and control your Apple Home accessories, scenes and cameras. Nothing leaves this iPad."
        case .denied, .restricted:
            "Apple Home access is turned off for HomePad in the iPad's Settings app."
        default:
            "Adding an accessory opens Apple's setup sheet for HomeKit and Matter accessories."
        }
    }
}
