import CoreAudio

/// Unwraps the first (interleaved) CoreAudio input buffer and hands its
/// frames to the pure `deinterleaveStereo`. The AudioBufferList decoding is
/// the boundary; the frame math and ring writes are the testable core.
extension UnsafeMutableAudioBufferListPointer {
    func deinterleavedStereo(
        into scratch: UnsafeMutablePointer<Float>,
        scratchCapacity: Int,
        leftRing: SampleRingBuffer,
        rightRing: SampleRingBuffer
    ) {
        guard let first = first, let data = first.mData else { return }
        let channels = Swift.max(Int(first.mNumberChannels), 1)
        let frameCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size / channels
        deinterleaveStereo(
            samples: data.assumingMemoryBound(to: Float.self),
            frameCount: frameCount, channels: channels,
            into: scratch, scratchCapacity: scratchCapacity,
            leftRing: leftRing, rightRing: rightRing)
    }
}

/// Real-time-safe deinterleave of `frameCount` interleaved frames into the two
/// channel rings. The scratch (≥ 2×`scratchCapacity`) holds the left frames in
/// its first half and the right in its second; a mono source (1 channel) feeds
/// both rings the same samples. Pure pointer arithmetic — no allocation — so it
/// stays safe on the real-time audio thread.
func deinterleaveStereo(
    samples: UnsafePointer<Float>, frameCount: Int, channels: Int,
    into scratch: UnsafeMutablePointer<Float>, scratchCapacity: Int,
    leftRing: SampleRingBuffer, rightRing: SampleRingBuffer
) {
    let channels = max(channels, 1)
    let frames = min(max(frameCount, 0), scratchCapacity)
    guard frames > 0 else { return }
    for frame in 0..<frames {
        let base = frame * channels
        scratch[frame] = samples[base]
        scratch[scratchCapacity + frame] = samples[base + min(channels - 1, 1)]
    }
    leftRing.write(scratch, count: frames)
    rightRing.write(scratch + scratchCapacity, count: frames)
}
