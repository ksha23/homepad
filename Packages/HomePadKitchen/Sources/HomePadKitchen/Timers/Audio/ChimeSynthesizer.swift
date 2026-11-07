import Foundation

/// Renders a `ChimeSound` loop as 16-bit mono WAV data that `AVAudioPlayer` can loop.
enum ChimeSynthesizer {
    static let sampleRate = 44_100.0

    static func wav(for sound: ChimeSound) -> Data {
        let pattern = sound.pattern
        let count = Int(pattern.loopLength * sampleRate)
        var samples = [Double](repeating: 0, count: count)
        for note in pattern.notes {
            render(note, voice: sound.voice, into: &samples)
        }
        let peak = samples.map(abs).max() ?? 1
        let scale = peak > 0.95 ? 0.95 / peak : 1
        let pcm = samples.map { Int16(max(-1, min(1, $0 * scale)) * Double(Int16.max)) }
        return wavHeader(sampleCount: pcm.count) + pcm.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func render(_ note: ChimeSound.Note, voice: ChimeSound.Voice, into samples: inout [Double]) {
        let start = Int(note.start * sampleRate)
        let length = Int(note.length * sampleRate)
        let partials: [(ratio: Double, gain: Double)] = switch voice {
        case .bell: [(1, 1), (2.76, 0.35), (5.4, 0.12)]
        case .beep: [(1, 1), (3, 0.2)]
        case .swell: [(1, 1), (2, 0.1)]
        }
        for offset in 0..<length where start + offset < samples.count {
            let t = Double(offset) / sampleRate
            let envelope: Double = switch voice {
            case .bell: min(1, t / 0.004) * exp(-t * 3.2)
            case .beep: min(1, t / 0.005) * min(1, (note.length - t) / 0.01)
            case .swell: sin(Double.pi * t / note.length)
            }
            var value = 0.0
            for partial in partials {
                value += partial.gain * sin(2 * Double.pi * note.frequency * partial.ratio * t)
            }
            samples[start + offset] += value * envelope * note.gain
        }
    }

    private static func wavHeader(sampleCount: Int) -> Data {
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
