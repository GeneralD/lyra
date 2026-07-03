import Atomics

/// Lock-free single-producer / single-consumer ring of mono `Float` samples.
///
/// The producer is the CoreAudio IOProc running on a real-time audio thread —
/// it must never allocate, block, or take a lock — and the sole consumer is
/// the spectrum Interactor pulling the newest window once per display frame.
/// A `ManagedAtomic` write index (monotonically increasing, masked into the
/// power-of-two storage) is the only synchronization: the producer publishes
/// with a releasing store after the samples land, and the consumer acquires it
/// before reading. Torn reads of a sample that is being overwritten at the far
/// end of the ring are tolerated by design — one stale float in a visualizer
/// window is invisible, and tolerating it is what keeps both sides wait-free.
public final class SampleRingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Float>
    private let writeIndex = ManagedAtomic<Int>(0)

    /// - Parameter capacity: rounded up to the next power of two.
    public init(capacity: Int) {
        let rounded = Self.nextPowerOfTwo(max(capacity, 2))
        self.capacity = rounded
        self.mask = rounded - 1
        self.storage = .allocate(capacity: rounded)
        storage.initialize(repeating: 0, count: rounded)
    }

    deinit {
        storage.deallocate()
    }

    /// Producer side (real-time thread): copies `count` samples in and then
    /// publishes them with a single releasing store. No allocation, no locks.
    public func write(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        let start = writeIndex.load(ordering: .relaxed)
        for offset in 0..<count { storage[(start + offset) & mask] = samples[offset] }
        writeIndex.store(start + count, ordering: .releasing)
    }

    /// Consumer side: the newest `count` samples, oldest first. Empty until
    /// the producer has written at least `count` samples, or when `count`
    /// exceeds the ring capacity.
    public func latest(_ count: Int) -> [Float] {
        guard count > 0, count <= capacity else { return [] }
        let end = writeIndex.load(ordering: .acquiring)
        guard end >= count else { return [] }
        return ((end - count)..<end).map { storage[$0 & mask] }
    }

    private static func nextPowerOfTwo(_ value: Int) -> Int {
        value <= 1 ? 1 : 1 << (Int.bitWidth - (value - 1).leadingZeroBitCount)
    }
}
