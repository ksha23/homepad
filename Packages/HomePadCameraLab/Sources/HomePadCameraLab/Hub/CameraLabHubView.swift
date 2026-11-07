import HomePadCore
import HomePadUI
import SwiftUI

/// The Camera Lab app: capability chips and a tile for every tool. It reopens
/// on the tool it was left on, or the hub when that tool shows the camera
/// (see `CameraLabRouter`).
struct CameraLabHubView: View {
    @Environment(CameraLab.self) private var lab
    @AppState(CameraLabAppState.tool) private var savedTool

    var body: some View {
        @Bindable var router = lab.router
        NavigationStack(path: $router.path) {
            AppScreen("Camera Lab") {
                GeometryReader { proxy in
                    let columns = proxy.size.width > proxy.size.height ? 4 : 3
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                            CapabilityRow(capabilities: lab.capabilities)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.l), count: columns),
                                      spacing: Theme.Spacing.l) {
                                ForEach(CameraLabTool.allCases) { tool in
                                    NavigationLink(value: tool) {
                                        FeatureTile(
                                            title: tool.title, subtitle: tool.subtitle, systemImage: tool.systemImage,
                                            tint: tool.tint, status: status(for: tool), isActive: isActive(tool)
                                        )
                                        .frame(height: tileHeight(columns: columns, in: proxy.size))
                                    }
                                    .buttonStyle(.pressable(scale: 0.97))
                                }
                            }
                        }
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CameraLabTool.self) { tool in
                CameraLabToolView(tool: tool)
            }
        }
        .onAppear {
            applyLaunchArgument()
            lab.router.restore(savedTool)
        }
        .onDisappear { lab.router.leave() }
        .onChange(of: lab.router.path) { _, path in savedTool = path.last }
    }

    /// `-CameraLabTool <id>` opens a tool directly (simulator screenshots, UI checks).
    private func applyLaunchArgument() {
        guard lab.router.path.isEmpty,
              let id = UserDefaults.standard.string(forKey: "CameraLabTool"),
              let tool = CameraLabTool(rawValue: id) else { return }
        lab.router.open(tool)
    }

    /// Tiles tall enough that the rows fill the screen below the capability chips.
    private func tileHeight(columns: Int, in size: CGSize) -> CGFloat {
        let rows = CGFloat((CameraLabTool.allCases.count + columns - 1) / columns)
        let chips: CGFloat = 52
        let room = size.height - chips - Theme.Spacing.l * rows - Theme.Spacing.xl
        return min(max(room / rows, 220), 340)
    }

    private func isActive(_ tool: CameraLabTool) -> Bool {
        switch tool {
        case .security: lab.security.isEnabled
        case .timelapse: lab.timelapse.isRunning
        default: false
        }
    }

    private func status(for tool: CameraLabTool) -> String? {
        let capabilities = lab.capabilities
        switch tool {
        case .security:
            if lab.security.isWatching { return "Watching now" }
            return lab.security.isEnabled ? "Waiting for schedule" : nil
        case .floorPlan:
            return capabilities.supportsRoomPlan ? nil : "Demo plan, no LiDAR here"
        case .groceries, .qr:
            return capabilities.supportsLiveScanner ? nil : "Type or sample codes here"
        case .documents:
            return capabilities.supportsDocumentCamera ? nil : "Photos only here"
        case .timelapse where lab.timelapse.isRunning:
            return "\(lab.timelapse.framesThisSession) frames so far"
        case .ask, .timelapse:
            return capabilities.hasBackCamera ? nil : (CameraCapabilities.isSimulator ? "Demo feed" : "No back camera")
        }
    }
}

/// The hardware chips at the top of the hub.
struct CapabilityRow: View {
    let capabilities: CameraCapabilities

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                chip("Back Camera", systemImage: "camera", isAvailable: capabilities.hasBackCamera)
                chip("LiDAR", systemImage: "dot.radiowaves.left.and.right", isAvailable: capabilities.hasLiDAR)
                chip("Multi-Camera", systemImage: "camera.on.rectangle", isAvailable: capabilities.supportsMultiCamera)
                chip("Live Scanner", systemImage: "text.viewfinder", isAvailable: capabilities.supportsLiveScanner)
                if CameraCapabilities.isSimulator {
                    chip("Simulator Demo Feed", systemImage: "sparkles.tv", isAvailable: true)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// A pill that says whether a hardware feature is present, with a checkmark or a dash.
    private func chip(_ title: String, systemImage: String, isAvailable: Bool) -> some View {
        GlassPill(title, systemImage: systemImage) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isAvailable ? Color.green : Color.secondary)
        }
        .foregroundStyle(isAvailable ? .primary : .secondary)
        .accessibilityValue(isAvailable ? "Available" : "Not available")
    }
}

/// Routes a tool to its screen.
struct CameraLabToolView: View {
    let tool: CameraLabTool
    @Environment(CameraLab.self) private var lab

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            AppHeader(tool.title, onBack: { lab.router.path.removeAll() }, backLabel: "Camera Lab")
                .padding([.horizontal, .top], Theme.Spacing.l)
            switch tool {
            case .ask: AskAboutThisView()
            case .documents: DocumentScannerView()
            case .groceries: GroceryScannerView()
            case .security: SecurityCameraView()
            case .qr: QRScannerView()
            case .floorPlan: FloorPlanScreen().padding([.horizontal, .bottom], Theme.Spacing.l)
            case .timelapse: TimelapseView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar(.hidden, for: .navigationBar)
    }
}
