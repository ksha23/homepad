import HomePadCore
import HomePadUI
import SwiftUI

/// Settings, Camera Lab. A grouped list like iOS Settings, with curated choices.
struct CameraLabSettingsPane: View {
    @Environment(AppServices.self) private var services
    @Environment(CameraLab.self) private var lab
    @State private var confirmDeletePlan = false

    var body: some View {
        Form {
            Section {
                CapabilityRow(capabilities: lab.capabilities)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Camera Lab uses the back camera, and LiDAR on iPad Pro, for tools HomeView does not have. Each tool borrows the camera only while it runs, and presence sensing pauses meanwhile.")
            }

            Section("Ask About This") {
                Toggle("Read Answers Aloud", isOn: services.settings.binding(CameraLabSettings.speakAnswers))
            }

            Section {
                TextField("List", text: services.settings.binding(CameraLabSettings.groceryListName))
            } header: {
                Text("Grocery Scanner")
            } footer: {
                Text("Scanned items go to this Reminders list. Barcodes are looked up in Open Food Facts, a free product database. Only the barcode is sent.")
            }

            SecurityStatusSection()
            SecurityScheduleSection()
            SecurityDetectionSection()
            SecurityStreamSection()
            SecurityWebhookSection()

            Section("Timelapse") {
                Picker("Interval", selection: services.settings.binding(CameraLabSettings.timelapseInterval)) {
                    ForEach(TimelapseInterval.allCases) { Text($0.title).tag($0) }
                }
                TextField("Album", text: services.settings.binding(CameraLabSettings.timelapseAlbum))
            }

            Section {
                Button("Use Demo Floor Plan") { lab.floorPlans.useDemo(accessories: services.smartHome.accessories) }
                Button("Delete Floor Plan", role: .destructive) { confirmDeletePlan = true }
                    .disabled(lab.floorPlans.plan == nil)
                    .confirmationDialog("Delete the floor plan and accessory positions?", isPresented: $confirmDeletePlan, titleVisibility: .visible) {
                        Button("Delete Floor Plan", role: .destructive) { lab.floorPlans.reset() }
                    }
            } header: {
                Text("Floor Plan")
            } footer: {
                Text(lab.capabilities.supportsRoomPlan
                     ? "Scan rooms from the Floor Plan app. The plan stays on this iPad."
                     : "Scanning needs an iPad Pro with LiDAR. The demo plan works everywhere.")
            }
        }
        .navigationTitle("Camera Lab")
    }
}
