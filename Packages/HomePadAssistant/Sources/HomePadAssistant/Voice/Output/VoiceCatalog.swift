import AVFoundation

/// Installed system voices, best first: Personal Voice (when allowed), then
/// premium, enhanced and default quality, in the current language.
@MainActor
enum VoiceCatalog {
    /// A voice row for the settings picker.
    struct Option: Identifiable, Hashable {
        let id: String
        let name: String
        let detail: String
    }

    static var languageCode: String { AVSpeechSynthesisVoice.currentLanguageCode() }

    /// Voices in the iPad's language, best first: Personal Voice, Premium, Enhanced,
    /// then the plain voices of the iPad's own region. Every regional variant counts
    /// (British, Australian, Indian English and so on), so a Premium voice downloaded
    /// for another region is not hidden behind the region's compact voices. At equal
    /// quality the iPad's own region comes first. Novelty voices are left out.
    static func voices() -> [AVSpeechSynthesisVoice] {
        let code = languageCode
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(base) && !isNovelty($0) }
            .filter { rank($0) > 1 || $0.language == code }
            .sorted { lhs, rhs in
                if rank(lhs) != rank(rhs) { return rank(lhs) > rank(rhs) }
                if (lhs.language == code) != (rhs.language == code) { return lhs.language == code }
                return lhs.name < rhs.name
            }
    }

    static func options() -> [Option] {
        voices().map { voice in
            Option(id: voice.identifier, name: voice.name, detail: label(for: voice))
        }
    }

    /// The chosen voice if still installed, else the best available one.
    static func voice(identifier: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let chosen = AVSpeechSynthesisVoice(identifier: identifier) { return chosen }
        return voices().first { !$0.voiceTraits.contains(.isPersonalVoice) } ?? AVSpeechSynthesisVoice(language: languageCode)
    }

    /// Every voice the app can see, for `-HomePadVoiceReport YES`: written to
    /// Documents/voice-report.txt, for finding why a downloaded voice is missing.
    static func writeReportIfAsked() {
        guard UserDefaults.standard.bool(forKey: "HomePadVoiceReport"),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let picked = voice(identifier: "")
        var lines = ["iPad language \(languageCode), Automatic picks \(picked?.name ?? "none") (\(picked?.language ?? "-"))", ""]
        for voice in AVSpeechSynthesisVoice.speechVoices().sorted(by: { ($0.language, $0.name) < ($1.language, $1.name) }) {
            let listed = voices().contains { $0.identifier == voice.identifier }
            lines.append("\(voice.language) | \(voice.name) | \(label(for: voice)) | listed \(listed) | \(voice.identifier)")
        }
        try? lines.joined(separator: "\n").write(to: folder.appendingPathComponent("voice-report.txt"), atomically: true, encoding: .utf8)
    }

    static var personalVoiceStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus {
        AVSpeechSynthesizer.personalVoiceAuthorizationStatus
    }

    /// Asks to use the person's own Personal Voice. Returns true when allowed.
    static func requestPersonalVoice() async -> Bool {
        await AVSpeechSynthesizer.requestPersonalVoiceAuthorization() == .authorized
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        if voice.voiceTraits.contains(.isPersonalVoice) { return 4 }
        switch voice.quality {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
    }

    private static func label(for voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        if voice.voiceTraits.contains(.isPersonalVoice) {
            quality = "Personal Voice"
        } else {
            switch voice.quality {
            case .premium: quality = "Premium"
            case .enhanced: quality = "Enhanced"
            default: quality = "Default"
            }
        }
        // Another region's voice says where it is from, such as "Premium, United Kingdom".
        guard voice.language != languageCode, let region = voice.language.split(separator: "-").last,
              let name = Locale.current.localizedString(forRegionCode: String(region)) else { return quality }
        return "\(quality), \(name)"
    }

    /// Joke voices such as Bubbles or Zarvox.
    private static func isNovelty(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.identifier.contains("speech.synthesis.voice")
    }
}
