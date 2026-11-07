#if os(iOS)
import AVFoundation

extension AVAudioPCMBuffer {
    /// A copy of the samples, for a `MicrophoneHub` subscriber that keeps them
    /// after its handler returns. The hub reuses the tap's buffer for the next
    /// slice of audio, so a subscriber that hops off the render thread copies
    /// first. Nil for an empty buffer.
    public func copied() -> AVAudioPCMBuffer? {
        guard frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }
}
#endif
