#if os(iOS)
import AVFoundation
import Foundation
import HomePadCore
import Observation

/// HomePad's intercom, installed as `services.intercom`.
///
/// Push to talk records a short AAC clip from the shared microphone and sends
/// it to one room or every HomePad. Arriving clips play with an
/// "Intercom from Kitchen" overlay. Typed announcements are spoken aloud.
@MainActor
@Observable
public final class IntercomHub: IntercomService {
    /// The clip lengths offered in Settings.
    public static let clipLengths: [TimeInterval] = [10, 20, 30]

    public private(set) var history: [IntercomRecord] = []
    /// The message playing (or waiting to be played) right now, for the overlay.
    public private(set) var current: IntercomRecord?
    public private(set) var isPlaying = false
    public private(set) var isRecording = false
    public private(set) var recordingStartedAt: Date?
    public private(set) var lastError: String?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let link: PeerLink
    @ObservationIgnored private let recorder = ClipRecorder()
    @ObservationIgnored private lazy var playback = IntercomPlayback(audioSession: services.audioSession)
    @ObservationIgnored private var autoStop: Task<Void, Never>?
    @ObservationIgnored private var recordingTarget = IntercomTarget.everyone
    /// Set when the button is released before recording actually started (for example during the permission prompt).
    @ObservationIgnored private var releasedEarly = false

    init(services: AppServices, link: PeerLink) {
        self.services = services
        self.link = link
    }

    func start() {
        link.on(.intercomClip) { [weak self] message, peer in self?.receiveClip(message, from: peer) }
        link.on(.intercomText) { [weak self] message, peer in self?.receiveText(message, from: peer) }
    }

    // MARK: IntercomService

    /// Room names of the household's HomePads.
    public var peers: [String] { link.homePads.map(\.name) }

    public func announce(text: String, audio: Data?, to peer: String?) async throws {
        let target = peer.flatMap { name in
            link.homePads.first { $0.id == name || $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }.map { IntercomTarget.device(id: $0.id) } ?? .everyone
        if let audio {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("intercom-\(UUID().uuidString).m4a")
            try audio.write(to: url)
            let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
            try await sendClip(at: url, duration: duration, to: target)
        } else {
            try await sendText(text, to: target)
        }
    }

    // MARK: Push to talk

    /// Starts push to talk. The clip goes to `target` on release, or when the length limit is reached.
    public func startRecording(to target: IntercomTarget) async {
        lastError = nil
        releasedEarly = false
        recordingTarget = target
        guard services.settings[CoreSettings.microphoneEnabled] else {
            lastError = "The microphone is turned off in Control Center."
            return
        }
        guard await ClipRecorder.ensurePermission() else {
            lastError = ClipRecorder.RecorderError.permissionDenied.errorDescription
            return
        }
        guard !releasedEarly else { return }
        let maxSeconds = services.settings[ConnectSettings.intercomMaxSeconds]
        do {
            try recorder.start(microphone: services.microphone, maxSeconds: maxSeconds)
            isRecording = true
            recordingStartedAt = Date()
            autoStop = Task { [weak self] in
                try? await Task.sleep(for: .seconds(maxSeconds))
                guard !Task.isCancelled, let self, self.isRecording else { return }
                await self.finishRecording()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Stops push to talk and sends the clip.
    public func finishRecording() async {
        guard isRecording else {
            releasedEarly = true
            return
        }
        autoStop?.cancel()
        isRecording = false
        recordingStartedAt = nil
        guard let clip = await recorder.stop() else {
            lastError = "That was too short to send."
            return
        }
        do {
            try await sendClip(at: clip.url, duration: clip.duration, to: recordingTarget)
        } catch {
            lastError = error.localizedDescription
        }
    }


    // MARK: Sending

    /// Sends an existing .m4a clip (also used by the Apple Watch bridge).
    public func sendClip(at url: URL, duration: TimeInterval, to target: IntercomTarget) async throws {
        let audio = try Data(contentsOf: url)
        let body = IntercomClipBody(clipID: UUID(), fromName: link.identity.name, duration: duration, format: "m4a")
        let message = try link.message(.intercomClip, body, attachment: audio)
        try await deliver(message, to: target)
        record(.sent, peer: name(of: target), text: nil, audioURL: url, duration: duration)
    }

    public func sendText(_ text: String, to target: IntercomTarget) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let message = try link.message(.intercomText, IntercomTextBody(fromName: link.identity.name, text: trimmed))
        try await deliver(message, to: target)
        record(.sent, peer: name(of: target), text: trimmed, audioURL: nil, duration: 0)
    }

    private func deliver(_ message: PeerMessage, to target: IntercomTarget) async throws {
        var peerID: String?
        if case .device(let id) = target { peerID = id }
        if peerID == nil, link.household == nil { throw PeerLinkError.notPaired }
        if try await link.send(message, toHomePad: peerID).isEmpty {
            throw PeerLinkError.peerUnavailable("No other HomePad")
        }
    }

    private func name(of target: IntercomTarget) -> String {
        switch target {
        case .everyone: "Everywhere"
        case .device(let id): link.peer(id)?.name ?? "HomePad"
        }
    }

    // MARK: Receiving and playback

    /// Plays a message from the history again.
    public func play(_ record: IntercomRecord) {
        current = record
        isPlaying = true
        let finish = { [weak self] in
            guard let self else { return }
            self.isPlaying = false
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if !self.isPlaying, self.current?.id == record.id { self.current = nil }
            }
        }
        if let url = record.audioURL {
            playback.play(url, completion: finish)
        } else if let text = record.text, services.settings[ConnectSettings.intercomSpeakText] {
            playback.speak(text, from: record.peerName, completion: finish)
        } else {
            finish()
        }
    }

    public func dismissCurrent() {
        playback.stop()
        current = nil
        isPlaying = false
    }

    private func receiveClip(_ message: PeerMessage, from peer: PeerDevice) {
        guard let body = try? message.content(IntercomClipBody.self), let audio = message.attachment else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("intercom-\(body.clipID.uuidString).m4a")
        guard (try? audio.write(to: url)) != nil else { return }
        let record = record(.received, peer: body.fromName, text: nil, audioURL: url, duration: body.duration)
        arrived(record)
    }

    private func receiveText(_ message: PeerMessage, from peer: PeerDevice) {
        guard let body = try? message.content(IntercomTextBody.self) else { return }
        arrived(record(.received, peer: body.fromName, text: body.text, audioURL: nil, duration: 0))
    }

    private func arrived(_ record: IntercomRecord) {
        services.events.post(.intercomReceived(from: record.peerName, text: record.text))
        services.events.post(.wake)
        let quiet = services.settings[ConnectSettings.intercomQuietAtNight] && services.displayCondition == .night
        if services.settings[ConnectSettings.intercomAutoPlay] && !quiet {
            play(record)
        } else {
            current = record   // overlay offers a Play button
        }
    }

    @discardableResult
    private func record(_ direction: IntercomRecord.Direction, peer: String, text: String?, audioURL: URL?, duration: TimeInterval) -> IntercomRecord {
        let record = IntercomRecord(id: UUID(), direction: direction, peerName: peer, text: text,
                                    audioURL: audioURL, duration: duration, date: Date())
        history.insert(record, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
        return record
    }
}
#endif
