import HomePadCore
import HomePadUI
import SwiftUI

/// The "Smart Home" settings pane: Home Assistant, this HomePad as a device in
/// Home Assistant, Apple Home, the Home layout, the doorbell and dashboards, as
/// one grouped Settings list.
struct SmartHomeSettingsView: View {
    static let paneID = "smarthome"

    @Environment(UnifiedSmartHomeService.self) private var service
    @State private var editor: Editor?

    private enum Editor: String, Identifiable {
        case favorites, layout
        var id: String { rawValue }
    }

    var body: some View {
        ScrollViewReader { proxy in
            form.onAppear {
                // A debug launch scrolls to one section for its screenshot.
                if SmartHomeLaunchOptions.atLaunch.settingsSection == "device" {
                    proxy.scrollTo(HomeAssistantDeviceSection.anchorID, anchor: .top)
                }
            }
        }
    }

    private var form: some View {
        Form {
            HomeAssistantSettingsSection()
            HomeAssistantDeviceSection()
            HomeKitSettingsSection()
            Section {
                Button("Favorites", systemImage: "star") { editor = .favorites }
                Button("Rooms and Accessories", systemImage: "square.grid.2x2") { editor = .layout }
            } header: {
                Text("Home Layout")
            } footer: {
                Text("Choose favorites, the order of rooms, what appears and how big each tile is. You can also long press a tile in the Home app.")
            }
            DoorbellSettingsSection()
            DashboardSettingsSection()
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .favorites: FavoritesEditorView()
            case .layout: LayoutEditorView()
            }
        }
    }
}
