import Foundation
import HomePadCore
import Testing
@testable import HomePadPresence

@Suite struct DutyCycleTests {
    private let policy = DutyCyclePolicy(config: DutyCycleConfig(activeFPS: 10, scanFPS: 2, cooldown: 20))
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func scansWhenNobodyHasBeenSeen() {
        #expect(policy.mode(for: DutyCycleInputs(), now: now) == .scanning(framesPerSecond: 2))
    }

    @Test func goesActiveOnPresenceAndCoolsDownToScanning() {
        var inputs = DutyCycleInputs(lastPresenceAt: now)
        #expect(policy.mode(for: inputs, now: now) == .active(framesPerSecond: 10))
        // Still active inside the cooldown.
        #expect(policy.mode(for: inputs, now: now.addingTimeInterval(19)) == .active(framesPerSecond: 10))
        // The scheduled transition is exactly when the cooldown ends.
        #expect(policy.nextTransition(for: inputs, now: now) == now.addingTimeInterval(20))
        // Back to scanning after it.
        #expect(policy.mode(for: inputs, now: now.addingTimeInterval(21)) == .scanning(framesPerSecond: 2))
        #expect(policy.nextTransition(for: inputs, now: now.addingTimeInterval(21)) == nil)
        // A new sighting extends active mode.
        inputs.lastPresenceAt = now.addingTimeInterval(21)
        #expect(policy.mode(for: inputs, now: now.addingTimeInterval(22)) == .active(framesPerSecond: 10))
    }

    @Test func stopsWhenStoppedOrInactive() {
        #expect(policy.mode(for: DutyCycleInputs(isStarted: false), now: now) == .off(.stopped))
        #expect(policy.mode(for: DutyCycleInputs(isAppActive: false, isMicrophoneAvailable: true), now: now) == .off(.appInactive))
    }

    @Test func cameraUnavailableFallsBackToMicrophone() {
        let claimed = DutyCycleInputs(camera: .unavailable(.cameraInUse), isMicrophoneAvailable: true)
        #expect(policy.mode(for: claimed, now: now) == .microphoneOnly(.cameraInUse))
        let off = DutyCycleInputs(camera: .unavailable(.cameraSettingOff), isMicrophoneAvailable: false)
        #expect(policy.mode(for: off, now: now) == .off(.cameraSettingOff))
    }

    @Test func thermalStateThrottlesAndFinallyStopsCamera() {
        var inputs = DutyCycleInputs(lastPresenceAt: now)
        inputs.thermalState = .fair
        #expect(policy.mode(for: inputs, now: now) == .active(framesPerSecond: 6))
        inputs.thermalState = .serious
        #expect(policy.mode(for: inputs, now: now) == .active(framesPerSecond: 3))
        inputs.lastPresenceAt = nil
        #expect(policy.mode(for: inputs, now: now) == .scanning(framesPerSecond: 1))
        inputs.thermalState = .critical
        #expect(policy.mode(for: inputs, now: now) == .off(.thermal))
        inputs.isMicrophoneAvailable = true
        #expect(policy.mode(for: inputs, now: now) == .microphoneOnly(.thermal))
    }

    @Test func backendSelectionFavorsEfficiency() {
        let trueDepth = SensingCapabilities(hasTrueDepth: true, hasFrontCamera: true, isSimulated: false)
        let rgbOnly = SensingCapabilities(hasTrueDepth: false, hasFrontCamera: true, isSimulated: false)
        let active = SensingMode.active(framesPerSecond: 10)
        let scanning = SensingMode.scanning(framesPerSecond: 2)

        // Face tracking only while someone is present.
        #expect(BackendSelector.kind(for: active, capabilities: trueDepth, preferTrueDepth: true, ambientLight: .normal) == .faceTracking)
        // A lit room scans with plain RGB, a dark one with infrared depth.
        #expect(BackendSelector.kind(for: scanning, capabilities: trueDepth, preferTrueDepth: true, ambientLight: .normal) == .frontCamera)
        #expect(BackendSelector.kind(for: scanning, capabilities: trueDepth, preferTrueDepth: true, ambientLight: .dark) == .depthScan)
        // RGB-only iPads and the TrueDepth opt-out use the front camera.
        #expect(BackendSelector.kind(for: active, capabilities: rgbOnly, preferTrueDepth: true, ambientLight: .dark) == .frontCamera)
        #expect(BackendSelector.kind(for: active, capabilities: trueDepth, preferTrueDepth: false, ambientLight: .dark) == .frontCamera)
        // Nothing runs when the camera is off.
        #expect(BackendSelector.kind(for: .microphoneOnly(.cameraInUse), capabilities: trueDepth, preferTrueDepth: true, ambientLight: nil) == nil)
    }
}
