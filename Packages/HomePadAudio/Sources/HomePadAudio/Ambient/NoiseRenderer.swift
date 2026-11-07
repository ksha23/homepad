import AVFoundation
import Synchronization

/// Render-thread state for sleep sounds. The main thread only writes the two
/// atomics (which sound, how loud). The audio thread owns the generators and
/// the gain ramp, so rendering never locks or allocates.
final class NoiseRenderer: @unchecked Sendable {
    private let soundIndex = Atomic<Int>(0)
    private let targetGainBits = Atomic<UInt32>(Float(0).bitPattern)
    private var left = NoiseGenerator(seed: 0x1234_5678)
    private var right = NoiseGenerator(seed: 0x8765_4321)
    private var ramp = GainRamp()

    /// The sound to render. Changing it while playing crossfades through the gain ramp.
    func setSound(_ sound: AmbientSound) {
        soundIndex.store(Self.index(of: sound), ordering: .relaxed)
    }

    /// The level the output glides toward, 0...1.
    func setTargetGain(_ gain: Float) {
        targetGainBits.store(max(0, min(1, gain)).bitPattern, ordering: .relaxed)
    }

    /// Fills a non-interleaved float buffer list. Called on the audio render thread.
    func render(frameCount: AVAudioFrameCount, bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let leftData = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        let rightData = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let sound = Self.sound(at: soundIndex.load(ordering: .relaxed))
        ramp.target = Float(bitPattern: targetGainBits.load(ordering: .relaxed))
        for frame in 0..<Int(frameCount) {
            let gain = ramp.next()
            leftData[frame] = left.next(sound) * gain
            rightData?[frame] = right.next(sound) * gain
        }
    }

    private static func index(of sound: AmbientSound) -> Int {
        switch sound {
        case .white: 0
        case .pink: 1
        case .brown: 2
        case .rain: 3
        }
    }

    private static func sound(at index: Int) -> AmbientSound {
        switch index {
        case 0: .white
        case 1: .pink
        case 2: .brown
        default: .rain
        }
    }
}
