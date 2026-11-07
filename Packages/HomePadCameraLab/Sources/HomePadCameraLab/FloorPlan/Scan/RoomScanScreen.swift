import HomePadUI
import RoomPlan
import SwiftUI

/// RoomPlan's live scanning view inside HomePad chrome: a rounded viewport,
/// big glass controls and one instruction at a time.
struct RoomScanScreen: View {
    static let owner = "cameralab.floorplan"

    let existingPlacements: [FloorPlan.AccessoryPlacement]
    let onFinish: (FloorPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var controller = RoomScanController()

    var body: some View {
        AppScreen("Scan Rooms", onClose: cancel) {
            ZStack(alignment: .bottom) {
                RoomCaptureViewRepresentable(controller: controller)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        StatusBadge(controller.rooms.isEmpty ? "Room 1" : "Room \(controller.rooms.count + (controller.phase == .scanning ? 1 : 0))",
                                    color: .teal)
                            .padding(Theme.Spacing.m)
                    }
                    .overlay(alignment: .top) {
                        if let instruction = controller.instruction {
                            Text(instruction)
                                .font(.title2.weight(.semibold))
                                .padding(.horizontal, Theme.Spacing.l)
                                .padding(.vertical, Theme.Spacing.s)
                                .glassEffect(.regular, in: Capsule())
                                .padding(Theme.Spacing.m)
                        }
                    }
                controls.padding(Theme.Spacing.l)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { controller.startRoom() }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: Theme.Spacing.m) {
            switch controller.phase {
            case .scanning:
                Button("Done with This Room", systemImage: "checkmark", action: controller.finishRoom)
                    .buttonStyle(.glassProminent)
            case .processing:
                ProgressView("Drawing the room").padding().glassEffect(.regular, in: Capsule())
            case .roomReady:
                Button("Scan Another Room", systemImage: "plus", action: controller.startRoom)
                    .buttonStyle(.glass)
                Button("Save Floor Plan", systemImage: "square.and.arrow.down", action: save)
                    .buttonStyle(.glassProminent)
            case .failed(let message):
                Text(message).padding().glassEffect(.regular, in: Capsule())
                Button("Try Again", systemImage: "arrow.clockwise", action: controller.startRoom)
                    .buttonStyle(.glass)
            }
        }
        .controlSize(.extraLarge)
    }

    private func save() {
        controller.stopAll()
        onFinish(RoomPlanAdapter.plan(from: controller.rooms, name: "My Home", keeping: existingPlacements))
        dismiss()
    }

    private func cancel() {
        controller.stopAll()
        dismiss()
    }
}

private struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let controller: RoomScanController

    func makeUIView(context: Context) -> RoomCaptureView { controller.captureView }
    func updateUIView(_ view: RoomCaptureView, context: Context) {}
}
