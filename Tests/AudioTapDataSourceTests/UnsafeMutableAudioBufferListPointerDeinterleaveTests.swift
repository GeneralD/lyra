import CoreAudio
import Testing

@testable import AudioTapDataSource

@Suite("deinterleaveStereo")
struct DeinterleaveStereoTests {
    private func makeScratch(_ capacity: Int) -> UnsafeMutablePointer<Float> {
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: capacity * 2)
        scratch.initialize(repeating: 0, count: capacity * 2)
        return scratch
    }

    @Test("splits interleaved stereo into the two channel rings")
    func stereoSplit() {
        // Interleaved L R L R.
        let samples: [Float] = [1, -1, 2, -2]
        let cap = 8
        let scratch = makeScratch(cap)
        defer { scratch.deallocate() }
        let left = SampleRingBuffer(capacity: cap)
        let right = SampleRingBuffer(capacity: cap)
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            deinterleaveStereo(
                samples: base, frameCount: 2, channels: 2,
                into: scratch, scratchCapacity: cap, leftRing: left, rightRing: right)
        }
        #expect(left.latest(2) == [1, 2])
        #expect(right.latest(2) == [-1, -2])
    }

    @Test("a mono source feeds both rings the same samples")
    func monoDuplicated() {
        let samples: [Float] = [3, 4, 5]
        let cap = 8
        let scratch = makeScratch(cap)
        defer { scratch.deallocate() }
        let left = SampleRingBuffer(capacity: cap)
        let right = SampleRingBuffer(capacity: cap)
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            deinterleaveStereo(
                samples: base, frameCount: 3, channels: 1,
                into: scratch, scratchCapacity: cap, leftRing: left, rightRing: right)
        }
        #expect(left.latest(3) == [3, 4, 5])
        #expect(right.latest(3) == [3, 4, 5])
    }

    @Test("frames beyond the scratch capacity are dropped")
    func cappedAtCapacity() {
        let samples = [Float](repeating: 1, count: 20)
        let cap = 4
        let scratch = makeScratch(cap)
        defer { scratch.deallocate() }
        let left = SampleRingBuffer(capacity: cap)
        let right = SampleRingBuffer(capacity: cap)
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            deinterleaveStereo(
                samples: base, frameCount: 20, channels: 1,
                into: scratch, scratchCapacity: cap, leftRing: left, rightRing: right)
        }
        #expect(left.latest(cap).count == cap)
        #expect(left.latest(cap + 1).isEmpty)
    }

    @Test("zero frames is a no-op")
    func zeroFrames() {
        let samples: [Float] = [0]
        let cap = 4
        let scratch = makeScratch(cap)
        defer { scratch.deallocate() }
        let left = SampleRingBuffer(capacity: cap)
        let right = SampleRingBuffer(capacity: cap)
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            deinterleaveStereo(
                samples: base, frameCount: 0, channels: 2,
                into: scratch, scratchCapacity: cap, leftRing: left, rightRing: right)
        }
        #expect(left.latest(1).isEmpty)
    }
}

@Suite("UnsafeMutableAudioBufferListPointer.deinterleavedStereo")
struct DeinterleavedStereoWrapperTests {
    @Test("unwraps a hand-built AudioBufferList and delegates to deinterleaveStereo")
    func delegatesToDeinterleaveStereo() {
        let cap = 8
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: cap * 2)
        scratch.initialize(repeating: 0, count: cap * 2)
        defer { scratch.deallocate() }
        let left = SampleRingBuffer(capacity: cap)
        let right = SampleRingBuffer(capacity: cap)

        var samples: [Float] = [1, -1, 2, -2]  // interleaved L R L R
        samples.withUnsafeMutableBufferPointer { buf in
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 2,
                    mDataByteSize: UInt32(buf.count * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(buf.baseAddress)))
            withUnsafeMutablePointer(to: &bufferList) { ptr in
                UnsafeMutableAudioBufferListPointer(ptr)
                    .deinterleavedStereo(
                        into: scratch, scratchCapacity: cap, leftRing: left, rightRing: right)
            }
        }
        #expect(left.latest(2) == [1, 2])
        #expect(right.latest(2) == [-1, -2])
    }
}
