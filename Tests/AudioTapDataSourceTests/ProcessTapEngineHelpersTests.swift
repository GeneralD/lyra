import Foundation
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
