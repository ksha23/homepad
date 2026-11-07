import AVFoundation
import HomePadCore
import HomePadUI
import SwiftUI

/// The yellow talk button for two-way audio. Asks for the microphone the first time,
/// claims recording from the shared audio session while talking, and releases it after.
struct TalkButton: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(AppServices.self) private var services
    let cameraID: HomeCamera.ID
    var size: CGFloat = Theme.Size.roundControl
    @State private var isTalking = false
    @State private var message: String?

    private static let audioOwner = "smarthome.talk"

    var body: some View {
        GlassIconButton(isTalking ? "waveform" : "mic.fill", label: isTalking ? "Stop Talking" : "Talk",
                        size: size, tint: .yellow, action: toggle)
            .symbolEffect(.variableColor.iterative, isActive: isTalking)
            .alert("Can't Talk Right Now", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .onDisappear { if isTalking { stop() } }
    }

    private func toggle() {
        if isTalking { stop() } else { start() }
    }

    private func start() {
        Task {
            guard await AVAudioApplication.requestRecordPermission() else {
                message = "HomePad needs the microphone to talk through the camera. You can allow it in the iPad's Settings app."
                return
            }
            services.audioSession.claim(.record, owner: Self.audioOwner)
            do {
                try await service.setTalking(true, cameraID: cameraID)
                isTalking = true
            } catch {
                services.audioSession.release(owner: Self.audioOwner)
                message = error.localizedDescription
            }
        }
    }

    private func stop() {
        isTalking = false
        services.audioSession.release(owner: Self.audioOwner)
        Task { try? await service.setTalking(false, cameraID: cameraID) }
    }
}
