import CoreAudio
import Dependencies
import Foundation

/// Owns one CoreAudio process-tap capture chain: process tap → private
/// aggregate device → IOProc deinterleaving the stereo mixdown into the
/// left/right ring buffers.
///
/// Construction performs the whole CoreAudio setup and fails (`nil`) on any
/// error — unknown pid, TCC denial, or a tap/aggregate/IOProc failure — after
/// rolling back whatever partial state was created. `stop()` is idempotent and
/// also runs on deinit, so a dropped engine never leaks CoreAudio objects. All
/// imperative CoreAudio calls go through the injected `AudioTapGateway` (#310)
/// so this control flow — guard order, rollback branches — is unit-testable
/// with a fake gateway, without live audio hardware.
@available(macOS 14.4, *)
final class ProcessTapEngine {
    private static let scratchCapacity = 4096

    /// The tap's actual sample rate in Hz, read from its stream format (#299).
    /// The process-tap mixdown follows the current output device, so this is
    /// 44.1 kHz, 48 kHz, or whatever the hardware runs at — the analyzer needs
    /// it to place Hz on the right FFT bins rather than assume 48 kHz.
    let sampleRate: Double

    private let leftRing: SampleRingBuffer
    private let rightRing: SampleRingBuffer
    /// What CoreAudio objects this engine currently owns. A single value
    /// instead of three independently-mutable handles (as it was before #310)
    /// so a combination that should never occur — e.g. an aggregate device
    /// without its tap — is unrepresentable rather than merely avoided by
    /// `init?`'s call order.
    private var state: LifecycleState = .empty
    private var scratch: UnsafeMutablePointer<Float>?

    init?(pid: Int, leftRing: SampleRingBuffer, rightRing: SampleRingBuffer) {
        @Dependency(\.audioTapGateway) var gateway
        self.leftRing = leftRing
        self.rightRing = rightRing

        let processObjects = processObjects(forSubtreeOf: pid)
        guard !processObjects.isEmpty else { return nil }

        let description = CATapDescription(privateStereoMixdownOf: processObjects)
        guard let tapID = gateway.createProcessTap(description) else { return nil }
        state = .tapped(tapID)

        // The tap's stream format is valid the moment the tap exists and
        // reflects the mixdown's rate (the output device's); the pure
        // `resolvedTapSampleRate` falls back to 48 kHz when it is unreadable.
        self.sampleRate = resolvedTapSampleRate(from: state.liveTapFormat)

        // A tap only produces audio when read through an aggregate device that
        // lists it. The aggregate is private and auto-starts the tap.
        guard
            let aggregateID = gateway.createAggregateDevice(description.aggregateDeviceDescription)
        else {
            state = state.rolledBack()
            return nil
        }
        state = .aggregated(tapID, aggregateID)

        // The IO block runs on a real-time audio thread: no allocation, no
        // locks, no Swift concurrency. It deinterleaves the first buffer into
        // the preallocated per-channel scratches and hands each to its
        // wait-free ring. The rings and scratches are captured directly (not
        // `self`) so CoreAudio holding the block never retain-cycles the
        // engine.
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: Self.scratchCapacity * 2)
        scratch.initialize(repeating: 0, count: Self.scratchCapacity * 2)
        self.scratch = scratch
        let capturedLeft = leftRing
        let capturedRight = rightRing
        let block: AudioDeviceIOBlock = { _, inInputData, _, _, _ in
            UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
                .deinterleavedStereo(
                    into: scratch, scratchCapacity: Self.scratchCapacity,
                    leftRing: capturedLeft, rightRing: capturedRight)
        }
        guard
            let ioProcID = gateway.createIOProc(aggregateID: aggregateID, block: block),
            gateway.start(aggregateID: aggregateID, ioProcID: ioProcID)
        else {
            state = state.rolledBack()
            return nil
        }
        state = .running(tapID, aggregateID, ioProcID)
    }

    deinit {
        stop()
        scratch?.deallocate()
    }

    /// Tears the capture chain down in reverse order of construction.
    /// Idempotent — safe to call from both the owner and deinit, since rolling
    /// back an already-`.empty` state destroys nothing.
    func stop() {
        state = state.rolledBack()
    }
}

@available(macOS 14.4, *)
extension ProcessTapEngine: AudioTapEngine {}
