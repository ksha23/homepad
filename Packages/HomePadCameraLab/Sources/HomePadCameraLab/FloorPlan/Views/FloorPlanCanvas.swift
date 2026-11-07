import HomePadCore
import HomePadUI
import SwiftUI

/// The plan with live accessory pins. Tap a pin to toggle it. While arranging,
/// drag pins to move them, or drop accessories from the palette onto the plan.
struct FloorPlanCanvas: View {
    @Environment(AppServices.self) private var services
    let plan: FloorPlan
    let store: FloorPlanStore
    let isArranging: Bool

    @State private var dragging: (id: String, location: CGPoint)?

    var body: some View {
        GeometryReader { geometry in
            let mapper = PlanMapper(bounds: plan.bounds, size: geometry.size, padding: 70)
            ZStack(alignment: .topLeading) {
                FloorPlanDrawing(plan: plan, mapper: mapper)
                ForEach(plan.placements) { placement in
                    if let accessory = services.smartHome.accessory(placement.accessoryID) {
                        pin(for: accessory, at: dragging?.id == accessory.id ? dragging!.location : mapper.point(placement.position), mapper: mapper)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { ids, location in
                guard isArranging, let id = ids.first, services.smartHome.accessory(id) != nil else { return false }
                store.place(id, at: mapper.planPoint(location))
                return true
            }
        }
        .nightModeAware()
    }

    private func pin(for accessory: HomeAccessory, at location: CGPoint, mapper: PlanMapper) -> some View {
        AccessoryPin(accessory: accessory, isArranging: isArranging)
            .position(location)
            .gesture(isArranging ? moveGesture(accessory.id, mapper: mapper) : nil)
            .onTapGesture { if !isArranging { toggle(accessory) } }
            .contextMenu {
                if isArranging {
                    Button("Remove from Plan", systemImage: "minus.circle", role: .destructive) {
                        store.removePlacement(accessory.id)
                    }
                }
            }
    }

    private func moveGesture(_ id: String, mapper: PlanMapper) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { value in dragging = (id, value.location) }
            .onEnded { value in
                store.place(id, at: mapper.planPoint(value.location))
                dragging = nil
            }
    }

    private func toggle(_ accessory: HomeAccessory) {
        guard let command = FloorPlanActions.command(for: accessory) else { return }
        Task { try? await services.smartHome.perform(command, on: accessory.id) }
    }
}
