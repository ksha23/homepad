import HomePadCore
import os
import SwiftUI

/// Marks the Faces app for measuring, as the shell marks the app zoom
/// (`ZoomSignposts`): My Faces, the gallery and the editor opening, each
/// editor page and distance change, each scroll of My Faces and the gallery,
/// and each widget drag on the Widgets page. Each shows in Instruments'
/// Points of Interest, so a Time Profiler trace shows what the main thread
/// does through it.
///
/// With `-HomePadFacesTrace YES` each also records the main thread's frame
/// rate and hitches (HomePadCore's `FPSMonitor`) in Documents/fps-trace.txt,
/// as `Faces.<name>`, so an iPad gives the same numbers as the simulator.
/// Without the flag no frames are counted, and signposts cost next to nothing
/// while nothing records them.
@MainActor
enum FacesPerfTrace {
    private static let signposter = OSSignposter(subsystem: "com.ksha23.homepad", category: .pointsOfInterest)
    private static var intervals: [String: OSSignpostIntervalState] = [:]
    private static let countsFrames = PhotoTrace.trace.isEnabled

    /// How long an opening or a page change is recorded: past its animation
    /// and the first drawing of what it brought in.
    static let momentDuration: TimeInterval = 1.5

    /// A screen opening or a page coming in, recorded for `momentDuration`.
    static func moment(_ name: String) {
        signposter.emitEvent("Faces", "\(name, privacy: .public)")
        if countsFrames { FPSMonitor.shared.start(name: "Faces.\(name)", duration: momentDuration) }
    }

    /// Starts recording something with no set length, such as a scroll.
    static func begin(_ name: String) {
        if let state = intervals[name] { signposter.endInterval("Faces", state) }
        intervals[name] = signposter.beginInterval("Faces", id: signposter.makeSignpostID(), "\(name, privacy: .public)")
        if countsFrames { FPSMonitor.shared.begin(name: "Faces.\(name)") }
    }

    /// Ends what `begin(_:)` started.
    static func end(_ name: String) {
        if let state = intervals.removeValue(forKey: name) { signposter.endInterval("Faces", state) }
        if countsFrames { FPSMonitor.shared.end(name: "Faces.\(name)") }
    }
}

extension View {
    /// Records each scroll of this scroll view under `name` (`FacesPerfTrace`),
    /// from the finger's first move until it comes to rest.
    func facesScrollTrace(_ name: String) -> some View {
        onScrollPhaseChange { old, new in
            if !old.isScrolling, new.isScrolling { FacesPerfTrace.begin(name) }
            if old.isScrolling, !new.isScrolling { FacesPerfTrace.end(name) }
        }
    }
}
