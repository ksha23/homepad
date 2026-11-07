import HomePadCore
import SwiftUI

/// A demo camera's snapshot: one drawn frame, taken again every ten seconds as
/// Home Assistant's stills are, with the time it was taken for the age label
/// instead of a clock drawn on it.
struct DemoStillView: View {
    let camera: HomeCamera
    /// False draws one frame and keeps it, for thumbnails.
    var refreshes = true
    @State private var capturedAt = Date()

    var body: some View {
        DemoCameraFeedView(camera: camera, date: capturedAt, showsClock: false)
            .preference(key: SnapshotDateKey.self, value: capturedAt)
            .task {
                guard refreshes else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    capturedAt = Date()
                }
            }
    }
}
