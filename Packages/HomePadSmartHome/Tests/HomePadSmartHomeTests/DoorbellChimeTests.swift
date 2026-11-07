import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// The doorbell chime: the sound HomePad draws for it, and when it stays silent.
@Suite("Doorbell chime")
struct DoorbellChimeTests {
    private let wav = DoorbellChimeSound.wav()

    private func uint32(at offset: Int) -> UInt32 {
        wav.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    private var samples: [Int16] {
        wav.subdata(in: 44..<wav.count).withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    }

    @Test func isAWaveFileOfTheWholeChime() {
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: wav.subdata(in: 8..<16), as: UTF8.self) == "WAVEfmt ")
        #expect(String(decoding: wav.subdata(in: 36..<40), as: UTF8.self) == "data")
        #expect(Int(uint32(at: 4)) == wav.count - 8)
        #expect(Int(uint32(at: 40)) == wav.count - 44)
        #expect(uint32(at: 24) == 44_100)
        let seconds = Double(wav.count - 44) / 2 / DoorbellChimeSound.sampleRate
        #expect(abs(seconds - DoorbellChimeSound.duration) < 0.01)
    }

    @Test func isClearWithoutClipping() {
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect(Double(peak) / Double(Int16.max) > DoorbellChimeSound.peak - 0.01)
        #expect(Double(peak) / Double(Int16.max) < DoorbellChimeSound.peak + 0.01)
        // Both bars sound: the second still rings well after it is struck.
        let second = Int((DoorbellChimeSound.notes[1].start + 0.3) * DoorbellChimeSound.sampleRate)
        let window = samples[second..<second + 2000].map { abs(Int($0)) }.max() ?? 0
        #expect(window > Int(Int16.max) / 10)
    }

    @Test func endsInSilence() {
        #expect(samples.first == 0)
        #expect(abs(Int(samples.last ?? 1)) < 10)
    }

    @MainActor
    @Test func ringsOnlyWhenNothingAsksForQuiet() {
        #expect(!DoorbellChime.isQuiet(isOn: true, quietAtNight: true, quietHours: false, condition: .active))
        #expect(!DoorbellChime.isQuiet(isOn: true, quietAtNight: true, quietHours: false, condition: .sleeping))
        #expect(DoorbellChime.isQuiet(isOn: false, quietAtNight: true, quietHours: false, condition: .active))
        #expect(DoorbellChime.isQuiet(isOn: true, quietAtNight: false, quietHours: true, condition: .active), "Quiet Hours in Control Center")
        #expect(DoorbellChime.isQuiet(isOn: true, quietAtNight: true, quietHours: false, condition: .night))
        #expect(!DoorbellChime.isQuiet(isOn: true, quietAtNight: false, quietHours: false, condition: .night))
    }
}
