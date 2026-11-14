import HomePadCore
import HomePadUI
import SwiftUI

/// Face enrollment with guidance, in the spirit of Face ID setup: a circular
/// preview, a segmented ring that fills per pose, and one big instruction.
struct EnrollmentView: View {
    let session: EnrollmentSession
    let close: () -> Void

    var body: some View {
        // Closing stops the camera. A finished setup is already saved.
        SheetScreen("Recognize \(session.member.name)", onClose: {
            session.cancel()
            close()
        }) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding([.horizontal, .bottom], Theme.Spacing.xl)
        }
        .onDisappear { session.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .ready:
            intro(actionTitle: "Get Started") { session.begin() }
        case .needsPermission:
            intro(actionTitle: "Continue") { Task { await session.requestAccessAndBegin() } }
        case .denied:
            PermissionPrompt(
                "Camera Access Is Off", message: "Allow camera access for HomePad in Settings to set up recognition.",
                systemImage: "camera.fill", state: .denied
            )
        case .unavailable(let message):
            EmptyStateView("Camera Unavailable", message: message, systemImage: "video.slash.fill")
        case .capturing:
            capturing
        case .learningDepth:
            learningDepth
        case .finished:
            EmptyStateView(
                "\(session.member.name) Is Set Up",
                message: "HomePad will show \(session.member.name)'s personal content after recognizing their face.",
                systemImage: "checkmark.circle.fill", actionTitle: "Done", action: close
            )
        case .failed(let message):
            EmptyStateView("Setup Did Not Finish", message: message, systemImage: "exclamationmark.triangle.fill",
                           actionTitle: "Try Again") { session.begin() }
        }
    }

    /// After the face is saved, while recognition keeps depth templates of it.
    private var learningDepth: some View {
        VStack(spacing: Theme.Spacing.l) {
            ZStack {
                AvatarView(member: session.member, size: 120)
                SegmentedProgressRing(
                    segments: session.depthNeeded, completed: session.depthLearned, current: 0, lineWidth: 10
                )
                .frame(width: 150, height: 150)
            }
            Text("Keep Looking at HomePad")
                .font(.largeTitle.bold())
            Text("HomePad is learning the shape of your face from its depth, so it can recognize you in the dark too. \(session.depthLearned) of \(session.depthNeeded).")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            GlassCapsuleButton("Skip", size: .large, isProminent: false) { session.skipDepth() }
        }
    }

    private func intro(actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            AvatarView(member: session.member, size: 120)
            Text("Set Up Face Recognition")
                .font(.largeTitle.bold())
            Text("Look at the iPad and move your head as shown. For the last two steps, sit back where you usually sit. It takes about half a minute. Your face data stays encrypted on this iPad and is never uploaded or synced.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            GlassCapsuleButton(actionTitle, size: .large, isProminent: true, action: action)
        }
    }

    private var capturing: some View {
        let step = session.currentStep ?? .center
        return VStack(spacing: Theme.Spacing.xl) {
            ZStack {
                preview
                    .frame(width: 320, height: 320)
                    .clipShape(Circle())
                SegmentedProgressRing(
                    segments: session.steps.count, completed: session.stepIndex,
                    current: session.stepProgress, lineWidth: 12
                )
                .frame(width: 360, height: 360)
            }
            VStack(spacing: Theme.Spacing.s) {
                Label(step.instruction, systemImage: step.systemImage)
                    .font(.title.weight(.semibold))
                    .contentTransition(.opacity)
                Text(session.hint.isEmpty ? " " : session.hint)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .animation(.smooth, value: step)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let previewSession = session.capture.previewSession {
            CameraPreview(session: previewSession, device: session.capture.previewDevice)
        } else {
            ZStack {
                Circle().fill(.primary.opacity(0.08))
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 160, weight: .ultraLight))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
