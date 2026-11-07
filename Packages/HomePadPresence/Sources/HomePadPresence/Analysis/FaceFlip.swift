import CoreGraphics
import Foundation

/// How a face's point in the camera image is turned before it goes into the
/// depth map: as ARKit projects it, or mirrored.
///
/// `ARCamera.projectPoint` in landscape right should put a face where it is in
/// the captured image. Should it be the other way round for the front camera
/// of one of the iPads, every face away from the middle would miss itself in
/// the depth map, and the depth person tracker would never start. `DepthSensing`
/// therefore tries the mirrors when a face misses, and uses one once it alone
/// finds the face five depth maps in a row. The trace says so when it does.
enum FaceFlip: CaseIterable, Equatable, Sendable {
    case none
    case across
    case upDown
    case both

    /// `point` (normalized, top-left origin) turned this way.
    func apply(_ point: CGPoint) -> CGPoint {
        switch self {
        case .none: point
        case .across: CGPoint(x: 1 - point.x, y: point.y)
        case .upDown: CGPoint(x: point.x, y: 1 - point.y)
        case .both: CGPoint(x: 1 - point.x, y: 1 - point.y)
        }
    }

    /// For the trace.
    var title: String {
        switch self {
        case .none: "as projected"
        case .across: "mirrored across"
        case .upDown: "mirrored up-down"
        case .both: "turned half way round"
        }
    }
}
