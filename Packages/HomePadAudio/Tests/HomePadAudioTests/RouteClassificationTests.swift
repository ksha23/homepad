import AVFoundation
import HomePadCore
import Testing
@testable import HomePadAudio

@Suite struct RouteClassificationTests {
    typealias Port = AudioRoutePort.PortType

    @Test func rawPortTypesMatchAVAudioSession() {
        #expect(Port.builtInSpeaker == AVAudioSession.Port.builtInSpeaker.rawValue)
        #expect(Port.builtInReceiver == AVAudioSession.Port.builtInReceiver.rawValue)
        #expect(Port.headphones == AVAudioSession.Port.headphones.rawValue)
        #expect(Port.bluetoothA2DP == AVAudioSession.Port.bluetoothA2DP.rawValue)
        #expect(Port.bluetoothLE == AVAudioSession.Port.bluetoothLE.rawValue)
        #expect(Port.bluetoothHFP == AVAudioSession.Port.bluetoothHFP.rawValue)
        #expect(Port.airPlay == AVAudioSession.Port.airPlay.rawValue)
        #expect(Port.usbAudio == AVAudioSession.Port.usbAudio.rawValue)
        #expect(Port.hdmi == AVAudioSession.Port.HDMI.rawValue)
    }

    @Test(arguments: [
        (Port.airPlay, "Living Room", AudioOutputKind.airPlay, false),
        (Port.builtInSpeaker, "Speaker", .builtInSpeaker, false),
        (Port.headphones, "Headphones", .wired, true),
        (Port.bluetoothA2DP, "Kyle's AirPods Pro", .bluetooth, true),
        (Port.bluetoothHFP, "AirPods Max", .bluetooth, true),
        (Port.bluetoothA2DP, "Bose QC Ultra", .bluetooth, true),
        (Port.bluetoothA2DP, "JBL Flip 6", .bluetooth, false),
        (Port.bluetoothA2DP, "Beats Pill", .bluetooth, false),
        (Port.bluetoothA2DP, "Echo Buds", .bluetooth, true),
        (Port.bluetoothA2DP, "Sonos Roam", .bluetooth, false),
        (Port.usbAudio, "USB-C EarPods", .wired, true),
        (Port.usbAudio, "Scarlett 2i2", .wired, false),
        (Port.hdmi, "LG TV", .wired, false),
    ])
    func classifiesPorts(portType: String, name: String, kind: AudioOutputKind, isHeadphones: Bool) {
        let port = AudioRoutePort(name: name, uid: "uid", portType: portType)
        #expect(port.kind == kind)
        #expect(port.isHeadphones == isHeadphones)
    }

    @Test func namesRoutes() {
        let living = AudioRoutePort(name: "Living Room", uid: "a", portType: Port.airPlay)
        let kitchen = AudioRoutePort(name: "Kitchen", uid: "b", portType: Port.airPlay)
        let office = AudioRoutePort(name: "Office", uid: "c", portType: Port.airPlay)
        let speaker = AudioRoutePort(name: "Speaker", uid: "d", portType: Port.builtInSpeaker)
        #expect(RouteNaming.routeName(for: []) == "iPad")
        #expect(RouteNaming.routeName(for: [speaker]) == "iPad")
        #expect(RouteNaming.routeName(for: [living]) == "Living Room")
        #expect(RouteNaming.routeName(for: [living, kitchen]) == "Living Room and Kitchen")
        #expect(RouteNaming.routeName(for: [living, kitchen, office]) == "Living Room and 2 more")
        // A stereo pair reports the same name twice.
        #expect(RouteNaming.routeName(for: [living, AudioRoutePort(name: "Living Room", uid: "e", portType: Port.airPlay)]) == "Living Room")
    }

    @Test func namesTheMusicSpeakers() {
        #expect(MusicAirPlayVolume.speakerName([]) == nil)
        #expect(MusicAirPlayVolume.speakerName(["Speaker"]) == "iPad")
        #expect(MusicAirPlayVolume.speakerName(["Back Stereo Pair"]) == "Back Stereo Pair")
        #expect(MusicAirPlayVolume.speakerName(["Back Stereo Pair", "Bedroom", "Bedroom"]) == "Back Stereo Pair and Bedroom")
    }

    @Test func mapsPortsToOutputs() {
        #expect(RouteNaming.outputs(for: []).map(\.id) == ["builtin"])
        let outputs = RouteNaming.outputs(for: [
            AudioRoutePort(name: "Speaker", uid: "Built-In", portType: Port.builtInSpeaker),
            AudioRoutePort(name: "Kitchen", uid: "AA:BB", portType: Port.airPlay),
        ])
        #expect(outputs.map(\.id) == ["builtin", "route:AA:BB"])
        #expect(outputs.map(\.name) == ["iPad", "Kitchen"])
        #expect(outputs.allSatisfy { $0.isActive })
    }

    @Test func promptsOnlyWhenPlayingAwayFromPreferredSpeaker() {
        let living = AudioRoutePort(name: "Living Room", uid: "a", portType: Port.airPlay)
        let kitchen = AudioRoutePort(name: "Kitchen", uid: "b", portType: Port.airPlay)
        let airPods = AudioRoutePort(name: "AirPods Pro", uid: "c", portType: Port.bluetoothA2DP)
        let speaker = AudioRoutePort(name: "Speaker", uid: "d", portType: Port.builtInSpeaker)

        #expect(!RoutePromptPolicy.shouldPrompt(preferredSpeaker: "", enabled: true, ports: [speaker]))
        #expect(!RoutePromptPolicy.shouldPrompt(preferredSpeaker: "Living Room", enabled: false, ports: [speaker]))
        #expect(RoutePromptPolicy.shouldPrompt(preferredSpeaker: "Living Room", enabled: true, ports: [speaker]))
        #expect(RoutePromptPolicy.shouldPrompt(preferredSpeaker: "Living Room", enabled: true, ports: [kitchen]))
        #expect(!RoutePromptPolicy.shouldPrompt(preferredSpeaker: "living room", enabled: true, ports: [living, kitchen]))
        #expect(!RoutePromptPolicy.shouldPrompt(preferredSpeaker: "Living Room", enabled: true, ports: [airPods]))
        #expect(!RoutePromptPolicy.shouldPrompt(preferredSpeaker: "iPad", enabled: true, ports: [speaker]))
    }

    @Test func sessionNeedFollowsMicrophonePreference() {
        #expect(PlaybackSessionClaimer.need(preferMicrophone: false) == .longFormPlayback)
        #expect(PlaybackSessionClaimer.need(preferMicrophone: true) == .mediaPlayback)
    }
}
