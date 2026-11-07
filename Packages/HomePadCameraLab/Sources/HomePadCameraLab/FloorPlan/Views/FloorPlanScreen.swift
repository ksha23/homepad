import HomePadCore
import HomePadUI
import SwiftUI

/// The Floor Plan app (app id "floorplan"): HomePad chrome around the plan.
struct FloorPlanAppView: View {
    var body: some View {
        AppScreen("Floor Plan") {
            FloorPlanScreen()
        }
    }
}

/// The plan with its controls. Shown by the Floor Plan app and inside Camera Lab.
struct FloorPlanScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(CameraLab.self) private var lab
    @State private var isArranging = false
    @State private var showingScanner = false
    @State private var scanProblem: String?

    private var store: FloorPlanStore { lab.floorPlans }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            controls
            if let plan = store.plan {
                HStack(alignment: .top, spacing: Theme.Spacing.l) {
                    FloorPlanCanvas(plan: plan, store: store, isArranging: isArranging)
                        .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    if isArranging {
                        AccessoryPalette(plan: plan)
                            .frame(width: 340)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            } else {
                GlassTile { emptyState }
            }
        }
        .animation(.smooth, value: isArranging)
        .fullScreenCover(isPresented: $showingScanner, onDismiss: { lab.broker.release(RoomScanScreen.owner) }) {
            RoomScanScreen(existingPlacements: store.plan?.placements ?? []) { plan in
                store.replaceGeometry(with: plan)
            }
            .coverScreenMargin()
            .coverHomeBar()
            .environment(lab)
        }
        .onAppear {
            if store.plan == nil, !lab.capabilities.supportsRoomPlan {
                store.useDemo(accessories: services.smartHome.accessories)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let plan = store.plan {
                Text(plan.isDemo ? "Demo plan" : plan.name).font(.title3).foregroundStyle(.secondary)
            }
            if let scanProblem {
                Label(scanProblem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Spacer()
            if store.plan != nil {
                Toggle(isOn: $isArranging) { Label("Arrange", systemImage: "hand.draw") }
                    .toggleStyle(.button)
                    .buttonStyle(.glass)
            }
            if lab.capabilities.supportsRoomPlan {
                Button(store.plan == nil || store.plan?.isDemo == true ? "Scan Rooms" : "Rescan", systemImage: "camera.metering.matrix", action: startScan)
                    .buttonStyle(.glassProminent)
            }
            Menu {
                Button("Use Demo Plan", systemImage: "square.split.bottomrightquarter") {
                    store.useDemo(accessories: services.smartHome.accessories)
                }
                Button("Delete Plan", systemImage: "trash", role: .destructive) { store.reset() }
                    .disabled(store.plan == nil)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .buttonStyle(.glassIcon(size: Theme.Size.minTapTarget))
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var emptyState: some View {
        if lab.capabilities.supportsRoomPlan {
            EmptyStateView(
                "No Floor Plan Yet",
                message: "Walk around each room with the iPad's LiDAR camera. HomePad draws the walls, doors, windows and furniture, then you place your accessories.",
                systemImage: "camera.metering.matrix", actionTitle: "Scan Rooms", action: startScan
            )
        } else {
            EmptyStateView(
                "LiDAR Needed to Scan",
                message: "Scanning needs an iPad Pro with LiDAR. You can still try the demo plan with your accessories.",
                systemImage: "square.split.bottomrightquarter", actionTitle: "Use Demo Plan",
                action: { store.useDemo(accessories: services.smartHome.accessories) }
            )
        }
    }

    private func startScan() {
        if case .denied(let reason) = lab.broker.acquire(RoomScanScreen.owner, title: "Floor Plan", camera: .back, usesSystemCapture: true) {
            scanProblem = reason
            return
        }
        scanProblem = nil
        isArranging = false
        showingScanner = true
    }
}
