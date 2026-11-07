import HomePadCore
import HomePadUI
import SwiftUI

/// Settings > Presence & Privacy. A grouped Form with curated choices:
/// sensors, gestures, face recognition, how long a profile stays, sound
/// alerts and live status.
struct PresenceSettingsPane: View {
    let presence: LivePresenceService
    @Environment(AppServices.self) private var services
    @State private var enrolling: EnrollmentSession?
    private static let liveStatusID = "presence.liveStatus"

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                permissionSection
                SensingSettingsSection(presence: presence)
                FaceRecognitionSection(presence: presence) { member in startEnrollment(for: member) }
                ProfilesSection()
                SoundAlertsSection(sounds: presence.sounds)
                LiveStatusSection(presence: presence)
                    .id(Self.liveStatusID)
            }
            .task { await scrollToStatusIfRequested(proxy) }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .sheet(item: $enrolling) { session in
            EnrollmentView(session: session) { enrolling = nil }
                .interactiveDismissDisabled(session.phase == .capturing)
        }
        .onAppear(perform: openDebugEnrollmentIfRequested)
    }

    @ViewBuilder
    private var permissionSection: some View {
        let camera = CameraPermission.status
        let microphone = MicrophonePermission.status
        if !presence.capabilities.isSimulated, camera != .granted || microphone != .granted {
            Section {
                if camera == .undetermined {
                    PermissionPrompt(
                        "Notice When Someone Is Nearby",
                        message: "HomePad uses the front camera to wake up, adapt to your distance and recognize household members. Video is analyzed on this iPad and never stored or sent anywhere.",
                        systemImage: "camera.fill", state: .ask, style: .row
                    ) { await presence.requestPermissions() }
                } else if camera == .denied {
                    PermissionPrompt(
                        "Camera Access Is Off",
                        message: "Presence sensing, recognition and gestures need the camera. Turn it on in Settings.",
                        systemImage: "camera.fill", state: .denied, style: .row
                    )
                }
                if microphone == .undetermined {
                    PermissionPrompt(
                        "Hear Alarms and Doorbells",
                        message: "HomePad can listen for smoke alarms, doorbells and other sounds. Audio is analyzed on this iPad and never recorded.",
                        systemImage: "mic.fill", state: .ask, style: .row
                    ) { await presence.requestPermissions() }
                } else if microphone == .denied {
                    PermissionPrompt(
                        "Microphone Access Is Off",
                        message: "Sound alerts need the microphone. Turn it on in Settings.",
                        systemImage: "mic.slash.fill", state: .denied, style: .row
                    )
                }
            }
        }
    }

    private func startEnrollment(for member: HouseholdMember) {
        let capture: any EnrollmentCapture = presence.capabilities.isSimulated
            ? SimulatedEnrollmentCapture(memberID: member.id)
            : CameraEnrollmentCapture(useTrueDepth: services.settings[PresenceSettings.useTrueDepth])
        enrolling = EnrollmentSession(member: member, services: services, recognition: presence.recognition, capture: capture)
    }

    /// `-HomePadPresencePane status` scrolls to Live Status for screenshots.
    private func scrollToStatusIfRequested(_ proxy: ScrollViewProxy) async {
        guard PresenceLaunchOptions.current.debugPane == .status else { return }
        try? await Task.sleep(for: .milliseconds(500))
        proxy.scrollTo(Self.liveStatusID, anchor: .top)
    }

    /// `-HomePadPresencePane enroll` opens enrollment for the first member, and
    /// in simulated mode starts the scripted capture right away.
    private func openDebugEnrollmentIfRequested() {
        guard PresenceLaunchOptions.current.debugPane == .enroll, enrolling == nil,
              let member = services.household.members.first else { return }
        startEnrollment(for: member)
        if presence.capabilities.isSimulated { enrolling?.begin() }
    }
}
