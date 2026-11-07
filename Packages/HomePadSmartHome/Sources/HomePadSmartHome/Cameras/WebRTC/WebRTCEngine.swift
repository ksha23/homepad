import HomePadCore
import WebRTC

/// The app's one WebRTC peer connection factory and its audio device. Made the
/// first time a camera plays over WebRTC, then kept: the factory's threads sit
/// idle between sessions.
@MainActor
final class WebRTCEngine {
    let audioDevice: WebRTCAudioDevice
    private var madeFactory: RTCPeerConnectionFactory?

    init(audioSession: AudioSessionCoordinator, microphone: MicrophoneHub) {
        audioDevice = WebRTCAudioDevice(audioSession: audioSession, microphone: microphone)
    }

    var factory: RTCPeerConnectionFactory {
        if let madeFactory { return madeFactory }
        _ = Self.setUpOnce
        // H.264 through VideoToolbox, VP8, VP9 and AV1, as go2rtc may send any of them.
        let factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory(),
            audioDevice: audioDevice
        )
        madeFactory = factory
        return factory
    }

    private static let setUpOnce: Void = {
        RTCInitializeSSL()
        // WebRTC's own log can quote session descriptions, which carry ICE
        // passwords, so it stays silent. HomePad logs session states itself.
        RTCSetMinDebugLogLevel(.none)
    }()
}
