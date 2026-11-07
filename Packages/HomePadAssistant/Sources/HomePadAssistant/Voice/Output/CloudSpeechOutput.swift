import AVFoundation
import Foundation
import HomePadCore

/// Reads text with OpenAI's text to speech (`/audio/speech`). Optional, off by
/// default, because it sends answers to OpenAI.
@MainActor
final class CloudSpeechOutput: NSObject, SpeechOutput {
    static let model = "gpt-4o-mini-tts"

    private let baseURL: URL
    private let apiKey: String
    private let voice: CloudVoice
    private let transport: HTTPTransport
    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?

    init(baseURL: URL, apiKey: String, voice: CloudVoice, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.voice = voice
        self.transport = transport
    }

    /// The request body, separate for testing.
    static func body(text: String, voice: CloudVoice) -> JSONValue {
        [
            "model": .string(model), "voice": .string(voice.rawValue), "input": .string(text),
            "response_format": "mp3", "instructions": "Speak warmly and clearly, like a helpful home assistant.",
        ]
    }

    func speak(_ text: String) async throws {
        var request = URLRequest.jsonPost(baseURL.appending(path: "audio/speech"), body: Self.body(text: text, voice: voice),
                                          headers: ["Authorization": "Bearer \(apiKey)"])
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let audio = try await transport.data(for: request)
        try Task.checkCancellation()
        let player = try AVAudioPlayer(data: audio)
        player.delegate = self
        self.player = player
        await withCheckedContinuation { continuation in
            finished = continuation
            if !player.play() { finish() }
        }
    }

    func stop() {
        player?.stop()
        finish()
    }

    private func finish() {
        player = nil
        finished?.resume()
        finished = nil
    }
}

extension CloudSpeechOutput: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }
}
