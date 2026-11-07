import CryptoKit
import Foundation
import HomePadCore
import Observation
import Testing
@testable import HomePadConnect

/// A media service that records what it was asked to do.
@MainActor
@Observable
final class RecordingMediaService: MediaSeeking {
    var nowPlaying: NowPlaying?
    var outputs: [AudioOutput] = [
        AudioOutput(id: "builtin", name: "iPad", kind: .builtInSpeaker, isActive: true),
        AudioOutput(id: "ha:media_player.kitchen", name: "Kitchen HomePod", kind: .homeAssistantPlayer, volume: 0.3),
    ]
    var currentRouteName = "iPad"
    var canSeek = true
    var searchResult = "Blue in Green"
    var searchError: Error?
    private(set) var calls: [String] = []

    func play() async { calls.append("play") }
    func pause() async { calls.append("pause") }
    func nextTrack() async { calls.append("next") }
    func previousTrack() async { calls.append("previous") }
    func setVolume(_ volume: Double) async { calls.append("volume \(volume)") }
    func seek(to seconds: TimeInterval) async { calls.append("seek \(seconds)") }
    func select(outputID: AudioOutput.ID) async throws { calls.append("select \(outputID)") }

    func playSearch(_ query: String) async throws -> String {
        calls.append("search \(query)")
        if let searchError { throw searchError }
        return searchResult
    }
}

/// A phone and a HomePad joined in memory. Every message is encoded and
/// decoded with `MessageCodec` on the way, as on the network, and reaches the
/// same handlers a sealed session would call. No sockets, no pairing.
@MainActor
final class RemoteLoop {
    let media: RecordingMediaService
    let padServices: AppServices
    let padLink: PeerLink
    let server: RemoteControlServer
    let phoneLink: PeerLink
    let remote: RemoteHomePads
    let music: RemoteMusic
    let pad = PeerDevice(id: "pad-kitchen", name: "Kitchen", kind: .homePad, isConnected: true)
    let phone = PeerDevice(id: "phone-kyle", name: "Kyle's iPhone", kind: .iPhone, isConnected: true)
    /// What reached the HomePad and the phone, after the wire.
    private(set) var toPadLog: [PeerMessage] = []
    private(set) var toPhoneLog: [PeerMessage] = []

    init() {
        let media = RecordingMediaService()
        self.media = media
        let padServices = AppServices(settings: Self.freshSettings())
        padServices.media = media
        self.padServices = padServices
        padLink = PeerLink(services: padServices)
        server = RemoteControlServer(services: padServices, registry: ModuleRegistry(), link: padLink)
        phoneLink = PeerLink(services: AppServices(settings: Self.freshSettings()))
        remote = RemoteHomePads(link: phoneLink)
        music = RemoteMusic(link: phoneLink, remote: remote)

        server.start()
        remote.start()
        music.start()
        server.music.systemVolume = { 0.4 }
        server.music.deliver = { [unowned self] message, _ in self.toPhone(message) }
        remote.transmit = { [unowned self] message, _ in await self.toPad(message) }
    }

    /// The HomePad reports its status, as it does when a session opens.
    func connect(remoteVersion: Int? = RemoteProtocol.current) throws {
        var status = server.status()
        status.name = pad.name
        status.remoteVersion = remoteVersion
        toPhone(try padLink.message(.status, status))
    }

    func toPad(_ message: PeerMessage) async {
        let received = Self.overTheWire(message)
        toPadLog.append(received)
        if received.type == .command {
            for reply in await server.handle(command: received, from: phone) { toPhone(reply) }
        } else {
            padLink.dispatch(received, from: phone)
        }
    }

    func toPhone(_ message: PeerMessage) {
        let received = Self.overTheWire(message)
        toPhoneLog.append(received)
        phoneLink.dispatch(received, from: pad)
    }

    /// Lets queued tasks run, then waits for the HomePad's pushes to go out.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
        await server.music.waitUntilSent()
        for _ in 0..<5 { await Task.yield() }
    }

    func sent(_ type: PeerMessageType, toPhone: Bool = true) -> [PeerMessage] {
        (toPhone ? toPhoneLog : toPadLog).filter { $0.type == type }
    }

    static func overTheWire(_ message: PeerMessage) -> PeerMessage {
        // A codec failure here is a test failure, so crash loudly.
        try! MessageCodec.decode(MessageCodec.encode(message))
    }

    static func freshSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "connect.tests.\(UUID().uuidString)")!)
    }
}

/// Shows nothing, so tests never touch the notification center.
struct SilentApprovalNotifications: ApprovalNotifying {
    func show(_ prompt: ApprovalResponder.Prompt) {}
    func remove(_ id: UUID) {}
}

/// A HomePad and a member's phone joined in memory for personal device
/// approval, like `RemoteLoop`: every message crosses `MessageCodec` and
/// reaches the handlers a sealed session would call. The phone's key is a
/// software key and its Face ID always passes. Each side has its own clock.
@MainActor
final class ApprovalLoop {
    let padServices: AppServices
    let padLink: PeerLink
    let approver: PersonalDeviceApprover
    let phoneLink: PeerLink
    let phone: ApprovalResponder
    let pad = PeerDevice(id: "pad-kitchen", name: "Kitchen", kind: .homePad, isConnected: true)
    let phoneDevice = PeerDevice(id: "phone-kyle", name: "iPhone", kind: .iPhone, isConnected: true)
    let kyle = HouseholdMember(name: "Kyle", avatar: "🦊", isAdmin: true)
    let sam = HouseholdMember(name: "Sam", avatar: "🐼")
    let phoneKey = P256.Signing.PrivateKey()
    var padClock = Date(timeIntervalSince1970: 1_800_000_000)
    var phoneClock = Date(timeIntervalSince1970: 1_700_000_000)
    /// What the iPad's Face ID sheet answers when someone allows a link.
    var ownerPasses = true
    private(set) var ownerAsked = 0
    /// Devices the HomePad cannot reach.
    var unreachable: Set<String> = []
    private(set) var toPadLog: [PeerMessage] = []
    private(set) var toPhoneLog: [PeerMessage] = []

    init() {
        padServices = AppServices(settings: RemoteLoop.freshSettings())
        padServices.household.add(kyle)
        padServices.household.add(sam)
        padLink = PeerLink(services: padServices)
        padLink.identity = LocalIdentity(deviceID: pad.id, name: pad.name, kind: .homePad)
        approver = PersonalDeviceApprover(services: padServices, link: padLink)
        phoneLink = PeerLink(services: AppServices(settings: RemoteLoop.freshSettings()))
        phoneLink.identity = LocalIdentity(deviceID: phoneDevice.id, name: phoneDevice.name, kind: .iPhone)
        phone = ApprovalResponder(services: AppServices(settings: RemoteLoop.freshSettings()), link: phoneLink)
        approver.start()
        phone.start()

        approver.now = { [unowned self] in padClock }
        approver.verifyOwner = { [unowned self] _ in
            ownerAsked += 1
            return ownerPasses
        }
        approver.transmit = { [unowned self] message, peerID in
            guard !unreachable.contains(peerID) else { throw PeerLinkError.timedOut }
            toPhone(message)
        }
        phone.now = { [unowned self] in phoneClock }
        phone.sign = { [unowned self] data, _ in try phoneKey.signature(for: data).rawRepresentation }
        phone.publicKey = { [unowned self] in phoneKey.publicKey.rawRepresentation }
        phone.notifications = SilentApprovalNotifications()
        phone.transmit = { [unowned self] message, _ in toPad(message, from: phoneDevice) }
    }

    func toPad(_ message: PeerMessage, from device: PeerDevice) {
        let received = RemoteLoop.overTheWire(message)
        toPadLog.append(received)
        padLink.dispatch(received, from: device)
    }

    func toPhone(_ message: PeerMessage) {
        let received = RemoteLoop.overTheWire(message)
        toPhoneLog.append(received)
        phoneLink.dispatch(received, from: pad)
    }

    /// Lets queued tasks run.
    func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    /// Links the phone to `member` and allows it on the HomePad.
    func linkPhone(to member: HouseholdMember) async throws {
        await phone.requestState(of: pad.id)
        await settle()
        let choice = try #require(phone.states[pad.id]?.members.first { $0.id == member.id })
        await phone.linkMember(choice, on: pad.id)
        await settle()
        let pending = try #require(approver.pendingLinks.first)
        await approver.allow(pending)
        await settle()
    }

    /// The last request the phone got.
    func lastRequest() throws -> ApprovalRequest {
        try #require(toPhoneLog.last { $0.type == .approvalRequest }).content(ApprovalRequest.self)
    }

    func sent(_ type: PeerMessageType) -> [PeerMessage] {
        (toPhoneLog + toPadLog).filter { $0.type == type }
    }
}
