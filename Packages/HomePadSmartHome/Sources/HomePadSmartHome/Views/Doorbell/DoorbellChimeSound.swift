import Foundation

/// HomePad's own doorbell chime, drawn from sine waves rather than recorded:
/// two struck bars a major third apart, the high one and then the low one, the
/// way a mechanical door chime sounds. It renders as 16-bit mono WAV data that
/// `AVAudioPlayer` plays.
enum DoorbellChimeSound {
    static let sampleRate = 44_100.0
    /// The whole chime, with time for the second bar to ring out.
    static let duration = 2.6

    struct Note {
        let start: Double
        let frequency: Double
    }

    /// E5, then C5 half a second later.
    static let notes = [Note(start: 0, frequency: 659.26), Note(start: 0.55, frequency: 523.25)]

    /// A struck bar's overtones (its free-free modes) as frequency ratio, gain
    /// and how fast each fades. The higher ones die away first, so the attack
    /// clinks and the tail is a pure tone.
    private static let partials: [(ratio: Double, gain: Double, decay: Double)] = [
        (1, 1, 2.2), (2.756, 0.32, 5.5), (5.404, 0.1, 11),
    ]

    /// The loudest sample, so the chime is clear without being harsh.
    static let peak = 0.7

    static func wav() -> Data {
        let count = Int(duration * sampleRate)
        var samples = [Double](repeating: 0, count: count)
        for note in notes {
            render(note, into: &samples)
        }
        // A short fade at the very end, so the last sample is silent and nothing clicks.
        let fade = Int(0.05 * sampleRate)
        for index in max(count - fade, 0)..<count {
            samples[index] *= Double(count - index) / Double(fade)
        }
        let loudest = samples.map(abs).max() ?? 0
        let scale = loudest > 0 ? peak / loudest : 0
        let pcm = samples.map { Int16(($0 * scale) * Double(Int16.max)) }
        return header(sampleCount: pcm.count) + pcm.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func render(_ note: Note, into samples: inout [Double]) {
        let start = Int(note.start * sampleRate)
        for offset in 0..<(samples.count - start) {
            let time = Double(offset) / sampleRate
            // A 4 millisecond attack, as a hammer meets the bar.
            let attack = min(1, time / 0.004)
            var value = 0.0
            for partial in partials {
                value += partial.gain * exp(-time * partial.decay) * sin(2 * .pi * note.frequency * partial.ratio * time)
            }
            samples[start + offset] += value * attack
        }
    }

    private static func header(sampleCount: Int) -> Data {
        let dataSize = UInt32(sampleCount * 2)
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                       // fmt chunk size
        append(UInt16(1))                        // PCM
        append(UInt16(1))                        // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 2)           // byte rate
        append(UInt16(2))                        // block align
        append(UInt16(16))                       // bits per sample
        header.append(contentsOf: Array("data".utf8))
        append(dataSize)
        return header
    }
}
