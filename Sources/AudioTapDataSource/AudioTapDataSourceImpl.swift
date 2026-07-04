import Domain
import Foundation
import os

/// Live `AudioTapDataSource` backed by a CoreAudio process tap (#23).
///
/// Hosts below macOS 14.4 — the floor where `AudioHardwareCreateProcessTap`
/// behaves reliably (SDK declares 14.2, but real-world captures are unstable
/// before 14.4) — degrade to a permanent no-op: `startTap` returns `false` and
/// the spectrum overlay simply never animates.
public final class AudioTapDataSourceImpl: Sendable {
    /// Large enough for the biggest supported FFT window (4096) with slack for
    /// several IOProc cycles of overwrite headroom.
    private static let ringCapacity = 16384

    private let leftRing = SampleRingBuffer(capacity: ringCapacity)
    private let rightRing = SampleRingBuffer(capacity: ringCapacity)
    /// The live `ProcessTapEngine`, held as `AnyObject` because its type is
    /// `@available(macOS 14.4, *)` while this class must exist on macOS 14.0.
    private let engine = OSAllocatedUnfairLock<AnyObject?>(uncheckedState: nil)

    public init() {}
}

extension AudioTapDataSourceImpl: AudioTapDataSource {
    public func startTap(pid: Int) async -> Bool {
        guard #available(macOS 14.4, *) else { return false }
        // The old engine stops before the new one exists so the SPSC rings
        // never see two writers, and construction happens OUTSIDE the lock —
        // CoreAudio setup (potentially a first-run TCC prompt) must not stall
        // `latestSamples`' per-frame lock acquisition. The caller serializes
        // start/stop through a single processor task, so the two lock
        // sections cannot interleave with another mutation.
        let previous = engine.withLockUnchecked { current -> AnyObject? in
            defer { current = nil }
            return current
        }
        (previous as? ProcessTapEngine)?.stop()
        let created = ProcessTapEngine(pid: pid, leftRing: leftRing, rightRing: rightRing)
        engine.withLockUnchecked { $0 = created }
        return created != nil
    }

    public func stopTap() async {
        engine.withLockUnchecked { current in
            if #available(macOS 14.4, *) {
                (current as? ProcessTapEngine)?.stop()
            }
            current = nil
        }
    }

    public func latestSamples(count: Int) -> StereoSamples {
        guard engine.withLockUnchecked({ $0 != nil }) else { return StereoSamples() }
        return StereoSamples(left: leftRing.latest(count), right: rightRing.latest(count))
    }
}
