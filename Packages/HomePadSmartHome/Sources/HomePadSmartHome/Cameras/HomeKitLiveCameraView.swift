@preconcurrency import HomeKit
import SwiftUI

/// Live HomeKit video. Borrows the camera's stream from the shared hub while visible.
struct HomeKitLiveCameraView: View {
    let profile: HMCameraProfile
    let hub: HomeKitStreamHub

    var body: some View {
        ZStack {
            if let stream = hub.stream(for: profile) {
                HomeKitCameraSourceView(source: stream)
            } else {
                CameraPlaceholder(message: nil, isLoading: true)
            }
        }
        .onAppear { hub.acquire(profile) }
        .onDisappear { hub.release(profile) }
    }
}
