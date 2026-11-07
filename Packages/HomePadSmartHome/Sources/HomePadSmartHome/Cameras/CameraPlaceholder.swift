import HomePadCore
import HomePadUI
import SwiftUI

/// Shown while a feed connects or when it cannot play.
struct CameraPlaceholder: View {
    let message: String?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "video.slash.fill").font(.title)
                if let message {
                    Text(message).font(.callout).multilineTextAlignment(.center)
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
