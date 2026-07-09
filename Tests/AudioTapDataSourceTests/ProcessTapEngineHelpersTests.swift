import CoreAudio
import Foundation
import Testing

@testable import AudioTapDataSource

@Suite("tapSampleRate")
struct TapSampleRateTests {
    private func format(rate: Double) -> AudioStreamBasicDescription {
        var f = AudioStreamBasicDescription()
        f.mSampleRate = rate
        return f
    }

    @Test("positive rate is returned as-is — 44.1 kHz")
    func rate44100() {
        #expect(tapSampleRate(from: format(rate: 44100)) == 44100)
    }

    @Test("positive rate is returned as-is — 48 kHz")
    func rate48000() {
        #expect(tapSampleRate(from: format(rate: 48000)) == 48000)
    }

    @Test("zero rate yields nil — no audio stream")
    func zeroYieldsNil() {
        #expect(tapSampleRate(from: format(rate: 0)) == nil)
    }

    @Test("negative rate yields nil — malformed descriptor")
    func negativeYieldsNil() {
        #expect(tapSampleRate(from: format(rate: -1)) == nil)
    }
}

@Suite("resolvedTapSampleRate")
struct ResolvedTapSampleRateTests {
    private func format(rate: Double) -> AudioStreamBasicDescription {
        var f = AudioStreamBasicDescription()
        f.mSampleRate = rate
        return f
    }

    @Test("a readable positive rate is used as-is")
    func usesPositiveRate() {
        #expect(resolvedTapSampleRate(from: format(rate: 44100)) == 44100)
    }

    @Test("an unreadable format falls back to the 48 kHz mixdown default")
    func unreadableFallsBackTo48k() {
        #expect(resolvedTapSampleRate(from: nil) == 48000)
    }

    @Test("a malformed (non-positive) rate falls back to 48 kHz")
    func malformedFallsBackTo48k() {
        #expect(resolvedTapSampleRate(from: format(rate: 0)) == 48000)
        #expect(resolvedTapSampleRate(from: format(rate: -1)) == 48000)
    }
}

@Suite("CATapDescription(privateStereoMixdownOf:)")
struct ProcessTapDescriptionTests {
    @Test("the descriptor is private and never mutes the tapped process")
    func isPrivateAndUnmuted() {
        guard #available(macOS 14.4, *) else { return }
        let description = CATapDescription(privateStereoMixdownOf: [42])
        #expect(description.isPrivate)
        #expect(description.muteBehavior == .unmuted)
    }
}

@Suite("CATapDescription.aggregateDeviceDescription")
struct AggregateDeviceDescriptionTests {
    @Test("lists itself as the sole, drift-compensated sub-tap")
    func listsItselfAsSubTap() {
        guard #available(macOS 14.4, *) else { return }
        let description = CATapDescription(privateStereoMixdownOf: [42])
        let descriptor = description.aggregateDeviceDescription
        #expect(descriptor[kAudioAggregateDeviceNameKey] as? String == "lyra-spectrum-tap")
        #expect(descriptor[kAudioAggregateDeviceIsPrivateKey] as? Bool == true)
        #expect(descriptor[kAudioAggregateDeviceTapAutoStartKey] as? Bool == true)
        let tapList = descriptor[kAudioAggregateDeviceTapListKey] as? [[String: Any]]
        #expect(tapList?.count == 1)
        #expect(tapList?.first?[kAudioSubTapUIDKey] as? String == description.uuid.uuidString)
        #expect(tapList?.first?[kAudioSubTapDriftCompensationKey] as? Bool == true)
    }
}

@Suite("parentPid")
struct ParentPidTests {
    @Test("the current process's parent pid is readable and positive")
    func readsRealParentPid() {
        let parent = parentPid(of: getpid())
        #expect((parent ?? 0) > 0)
    }
}

@Suite("LifecycleState.liveTapFormat")
struct LiveTapFormatTests {
    @Test("no tap yet (.empty) yields no format")
    func emptyYieldsNil() {
        guard #available(macOS 14.4, *) else { return }
        #expect(LifecycleState.empty.liveTapFormat == nil)
    }

    @Test("an unknown tap object id yields no format")
    func unknownObjectYieldsNil() {
        // The CI runner satisfies macOS 14.4+, so the read against a
        // non-existent tap object actually runs, fails, and the property
        // reports nil — the caller then falls back to the 48 kHz mixdown
        // default.
        guard #available(macOS 14.4, *) else { return }
        let state = LifecycleState.tapped(AudioObjectID(kAudioObjectUnknown))
        #expect(state.liveTapFormat == nil)
    }
}

@Suite("LifecycleState.rolledBack")
struct LifecycleStateRolledBackTests {
    @Test("rolling back .empty destroys nothing and stays .empty")
    func emptyStaysEmpty() {
        guard #available(macOS 14.4, *) else { return }
        guard case .empty = LifecycleState.empty.rolledBack() else {
            Issue.record("expected .empty")
            return
        }
    }
}

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

@Suite("isInProcessSubtree")
struct IsInProcessSubtreeTests {
    // Synthetic tree: 300 → 200 → 100 → 1 (child → parent).
    private let parents: [pid_t: pid_t] = [300: 200, 200: 100, 100: 1]
    private func parent(_ pid: pid_t) -> pid_t? { parents[pid] }

    @Test("a pid equal to the root is in the subtree")
    func equalsRoot() {
        #expect(isInProcessSubtree(200, root: 200, parent: parent))
    }

    @Test("a descendant is in the subtree via the parent walk")
    func descendantIncluded() {
        #expect(isInProcessSubtree(300, root: 100, parent: parent))
    }

    @Test("an unrelated root is not an ancestor")
    func unrelatedExcluded() {
        #expect(!isInProcessSubtree(300, root: 999, parent: parent))
    }

    @Test("a nil pid is never in a subtree")
    func nilExcluded() {
        #expect(!isInProcessSubtree(nil, root: 100, parent: parent))
    }

    @Test("an unreadable parent stops the walk short")
    func brokenLookupStops() {
        // 400 has no known parent, so the walk can't reach root 100.
        #expect(!isInProcessSubtree(400, root: 100, parent: parent))
    }
}
