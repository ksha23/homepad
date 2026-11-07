import HomePadCore
import HomePadUI
import SwiftUI

/// One camera with its name: a live feed in the camera grid, a snapshot that
/// refreshes now and then in the Home app's row, labeled with its age ("2m ago")
/// as on HomeView.
struct CameraTile: View {
    let camera: HomeCamera
    var purpose: CameraFeedPurpose = .grid
    let onOpen: () -> Void
    /// When the snapshot on screen was taken. Live video has none.
    @State private var capturedAt: Date?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        CameraFeedView(camera: camera, purpose: purpose)
            .onPreferenceChange(SnapshotDateKey.self) { capturedAt = $0 }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .overlay(alignment: .bottomLeading) {
                Text(camera.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.xs)
                    .glassEffect(.regular, in: .capsule)
                    .padding(Theme.Spacing.s)
            }
            .overlay(alignment: .topTrailing) {
                if purpose == .still, let capturedAt {
                    SnapshotAgeLabel(capturedAt: capturedAt)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                }
            }
            .contentShape(shape)
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(camera.name) camera")
            .accessibilityAddTraits(.isButton)
            // The name's glass and the age sit on video in every appearance.
            .environment(\.colorScheme, .dark)
    }
}
