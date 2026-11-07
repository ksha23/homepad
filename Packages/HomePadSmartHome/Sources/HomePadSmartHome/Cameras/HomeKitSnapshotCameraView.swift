@preconcurrency import HomeKit
import SwiftUI

/// The latest HomeKit snapshot, refreshed every ten seconds while on screen,
/// with the time the camera took it for the age label. A battery camera that
/// is asleep keeps its older snapshot.
struct HomeKitSnapshotCameraView: View {
    let profile: HMCameraProfile
    /// False asks for one snapshot and stops, for thumbnails.
    var refreshes = true
    /// The snapshot on screen. HomeKit replaces `mostRecentSnapshot` a moment after
    /// each request, so it is read again once the new one has had time to arrive.
    @State private var source: HMCameraSnapshot?

    var body: some View {
        let snapshot = source ?? profile.snapshotControl?.mostRecentSnapshot
        HomeKitCameraSourceView(source: snapshot)
            .preference(key: SnapshotDateKey.self, value: snapshot?.captureDate)
            .task {
                // A new still every 10 seconds. Asking once, when the view appeared,
                // left a tile empty or showing the same still for as long as it stayed.
                while !Task.isCancelled {
                    profile.snapshotControl?.takeSnapshot()
                    try? await Task.sleep(for: .seconds(2))
                    if let latest = profile.snapshotControl?.mostRecentSnapshot { source = latest }
                    guard refreshes else { return }
                    try? await Task.sleep(for: .seconds(8))
                }
            }
    }
}
