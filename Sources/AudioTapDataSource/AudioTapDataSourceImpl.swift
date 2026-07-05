import Domain
import Foundation
import os

/// The real-world seam over a running CoreAudio process tap. Erasing
/// `ProcessTapEngine`'s `@available(macOS 14.4, *)` type behind a plain
/// protocol lets `AudioTapDataSourceImpl` — which must exist on macOS 14.0 —
/// hold it without scattering availability casts, and lets tests inject a fake
/// tap so the sample-rate tagging and start/stop paths are exercised without a
/// live audio device (#299).
protocol AudioTapEngine: AnyObject {
    /// The tap's real sample rate in Hz, fixed for the tap's lifetime.
    var sampleRate: Double { get }
    /// Tears the tap down; safe to call once per engine.
    func stop()
}

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
    /// The active tap, or `nil` when none is running.
    private let engine = OSAllocatedUnfairLock<(any AudioTapEngine)?>(uncheckedState: nil)
    /// Builds a tap for a pid over the shared rings, or `nil` when the OS is
    /// too old or CoreAudio setup fails. Injected so tests can supply a fake
    /// tap without a live audio device.
    private let makeEngine:
        @Sendable (_ pid: Int, _ left: SampleRingBuffer, _ right: SampleRingBuffer) ->
            (any AudioTapEngine)?

    public init() {
        self.makeEngine = { pid, left, right in
            guard #available(macOS 14.4, *) else { return nil }
            return ProcessTapEngine(pid: pid, leftRing: left, rightRing: right)
        }
    }

    /// Test seam: inject the tap-engine factory so the start/stop and
    /// sample-rate tagging paths run against a fake tap.
    init(
        makeEngine:
            @escaping @Sendable (Int, SampleRingBuffer, SampleRingBuffer) ->
            (any AudioTapEngine)?
    ) {
        self.makeEngine = makeEngine
    }
}

extension AudioTapDataSourceImpl: AudioTapDataSource {
    public func startTap(pid: Int) async -> Bool {
        // The old engine stops before the new one exists so the SPSC rings
        // never see two writers, and construction happens OUTSIDE the lock —
        // CoreAudio setup (potentially a first-run TCC prompt) must not stall
        // `latestSamples`' per-frame lock acquisition. The caller serializes
        // start/stop through a single processor task, so the two lock
        // sections cannot interleave with another mutation.
        let previous = engine.withLockUnchecked { current -> (any AudioTapEngine)? in
            defer { current = nil }
            return current
        }
        previous?.stop()
        let created = makeEngine(pid, leftRing, rightRing)
        engine.withLockUnchecked { $0 = created }
        return created != nil
    }

    public func stopTap() async {
        engine.withLockUnchecked { current in
            current?.stop()
            current = nil
        }
    }

    public func latestSamples(count: Int) -> StereoSamples {
        guard let tap = engine.withLockUnchecked({ $0 }) else { return StereoSamples() }
        // The rings are their own SPSC-safe stores, so reading them outside the
        // lock is fine; only the engine reference needs the lock. Tag the
        // window with the tap's real rate (#299) so the analyzer maps Hz to
        // FFT bins for the actual hardware rate, not a fixed 48 kHz.
        return StereoSamples(
            left: leftRing.latest(count), right: rightRing.latest(count),
            sampleRate: tap.sampleRate)
    }
}
