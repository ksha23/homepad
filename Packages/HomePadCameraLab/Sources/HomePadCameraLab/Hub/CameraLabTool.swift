import SwiftUI

/// The tools in the Camera Lab hub, in display order.
enum CameraLabTool: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case ask
    case documents
    case groceries
    case security
    case floorPlan
    case timelapse
    case qr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask About This"
        case .documents: "Recipe and Document Scanner"
        case .groceries: "Grocery Scanner"
        case .security: "Security Camera"
        case .floorPlan: "Floor Plan"
        case .timelapse: "Timelapse"
        case .qr: "QR Scanner"
        }
    }

    var subtitle: String {
        switch self {
        case .ask: "Point the back camera at something and ask."
        case .documents: "Recipe cards into Kitchen, flyers into Calendar, or any text."
        case .groceries: "Scan barcodes straight into your Groceries list."
        case .security: "Motion alerts and a live stream for Home Assistant."
        case .floorPlan: "Scan rooms with LiDAR and place your accessories."
        case .timelapse: "Watch a plant grow or the light change outside."
        case .qr: "Wi-Fi details, links and Matter or HomeKit codes."
        }
    }

    var systemImage: String {
        switch self {
        case .ask: "sparkle.magnifyingglass"
        case .documents: "doc.viewfinder"
        case .groceries: "barcode.viewfinder"
        case .security: "video.badge.waveform"
        case .floorPlan: "square.split.bottomrightquarter"
        case .timelapse: "timelapse"
        case .qr: "qrcode.viewfinder"
        }
    }

    /// True for tools that show the back camera as soon as they appear.
    /// Camera Lab never reopens straight into one of these.
    var showsCameraOnOpen: Bool {
        switch self {
        case .ask, .groceries, .security, .timelapse, .qr: true
        case .documents, .floorPlan: false
        }
    }

    var tint: Color {
        switch self {
        case .ask: .purple
        case .documents: .orange
        case .groceries: .green
        case .security: .red
        case .floorPlan: .teal
        case .timelapse: .yellow
        case .qr: .blue
        }
    }
}

/// Navigation inside the Camera Lab app. The assistant's `scan_groceries`
/// tool and the `-CameraLabTool <id>` launch argument jump straight to a tool.
///
/// The router outlives the app's view, so the app reopens on the tool it was
/// left on, except a tool that shows the camera: closing the app on one goes
/// back to the hub, so opening Camera Lab never turns the camera on by itself.
/// A tool asked for while the app is closed (the assistant) still opens.
@MainActor
@Observable
final class CameraLabRouter {
    var path: [CameraLabTool] = []

    func open(_ tool: CameraLabTool) {
        path = [tool]
    }

    /// The app closed: a tool that shows the camera goes back to the hub.
    func leave() {
        if path.last?.showsCameraOnOpen == true { path = [] }
    }

    /// The app opened on the hub: reopens a tool saved in an earlier launch,
    /// unless it shows the camera.
    func restore(_ tool: CameraLabTool?) {
        guard path.isEmpty, let tool, !tool.showsCameraOnOpen else { return }
        path = [tool]
    }
}
