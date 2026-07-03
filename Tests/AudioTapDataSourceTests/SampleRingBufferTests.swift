import Testing

@testable import AudioTapDataSource

@Suite("SampleRingBuffer")
struct SampleRingBufferTests {
    @Test("latest is empty before enough samples were written")
    func emptyBeforeFill() {
        let ring = SampleRingBuffer(capacity: 8)
        #expect(ring.latest(4).isEmpty)

        [Float](repeating: 1, count: 3).withUnsafeBufferPointer {
            ring.write($0.baseAddress!, count: $0.count)
        }
        #expect(ring.latest(4).isEmpty)
        #expect(ring.latest(3) == [1, 1, 1])
    }

    @Test("latest returns the newest samples oldest-first")
    func newestWindow() {
        let ring = SampleRingBuffer(capacity: 8)
        let samples: [Float] = [1, 2, 3, 4, 5, 6]
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) }
        #expect(ring.latest(4) == [3, 4, 5, 6])
    }

    @Test("writes wrap around the capacity and keep only the newest samples")
    func wrapAround() {
        let ring = SampleRingBuffer(capacity: 4)
        let samples: [Float] = [1, 2, 3, 4, 5, 6]
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) }
        #expect(ring.latest(4) == [3, 4, 5, 6])
    }

    @Test("requests beyond capacity yield empty")
    func beyondCapacity() {
        let ring = SampleRingBuffer(capacity: 4)
        let samples: [Float] = [1, 2, 3, 4]
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) }
        #expect(ring.latest(5).isEmpty)
    }

    @Test("capacity is rounded up to the next power of two")
    func capacityRounding() {
        let ring = SampleRingBuffer(capacity: 5)
        let samples: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        samples.withUnsafeBufferPointer { ring.write($0.baseAddress!, count: $0.count) }
        // Rounded to 8, so all 8 samples are retained.
        #expect(ring.latest(8) == samples)
    }
}
