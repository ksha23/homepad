import Observation

/// The sound of one camera view, shared between the screen that shows it (the
/// full-screen camera, the doorbell) and whichever feed plays in it. The screen
/// sets `isMuted` and reads what the feed reports to show the mute and talk
/// buttons. Feeds without sound leave everything off.
@MainActor
@Observable
final class CameraAudioControl {
    var isMuted: Bool
    /// The feed playing now carries sound.
    private(set) var hasAudio = false
    /// The feed playing now can send the microphone to the camera.
    private(set) var canHoldToTalk = false
    private(set) var isTalking = false

    @ObservationIgnored private var owner: ObjectIdentifier?
    @ObservationIgnored private var talk: ((Bool) async throws -> Void)?

    init(isMuted: Bool) {
        self.isMuted = isMuted
    }

    /// A feed reports its sound. The last feed to report owns the control, so one
    /// leaving late cannot clear the next one's state.
    func update(owner: ObjectIdentifier, hasAudio: Bool, canTalk: Bool, isTalking: Bool,
                talk: @escaping (Bool) async throws -> Void) {
        self.owner = owner
        self.talk = talk
        if self.hasAudio != hasAudio { self.hasAudio = hasAudio }
        if canHoldToTalk != canTalk { canHoldToTalk = canTalk }
        if self.isTalking != isTalking { self.isTalking = isTalking }
    }

    func release(owner: ObjectIdentifier) {
        guard self.owner == owner else { return }
        self.owner = nil
        talk = nil
        hasAudio = false
        canHoldToTalk = false
        isTalking = false
    }

    func setTalking(_ talking: Bool) async throws {
        try await talk?(talking)
    }
}
