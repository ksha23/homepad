import CoreGraphics
import HomePadCore

/// `-HomePadFacesTrace YES` writes Documents/faces-trace.txt: each depth
/// decision on the Photos face with what it was based on, so the face on the
/// wall and the editor's preview can be compared on a device.
@MainActor
enum PhotoTrace {
    static let trace = DebugTrace(file: "faces-trace.txt", argument: "HomePadFacesTrace")

    static func depth(_ frame: PhotoFrame, viewSize: CGSize, timeCoverage: Double?, subjectCoverage: Double?,
                      wantsDepth: Bool, uses: Bool, isNear: Bool, isThumbnail: Bool) {
        guard trace.isEnabled else { return }
        func size(_ size: CGSize) -> String { "\(Int(size.width))x\(Int(size.height))" }
        func number(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "-" }
        trace.log("depth \(frame.ref.id.suffix(14)) view \(size(viewSize)) image \(size(frame.imageSize)) "
                  + "mask \(frame.mask != nil) time \(number(timeCoverage)) subject \(number(subjectCoverage)) "
                  + "style \(wantsDepth) uses \(uses) near \(isNear) thumb \(isThumbnail)")
    }
}
