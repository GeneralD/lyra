import CoreAudio
import Foundation

/// Owns one CoreAudio process-tap capture chain: process tap → private
/// aggregate device → IOProc writing a mono mixdown into the ring buffer.
///
/// Construction performs the whole CoreAudio setup and fails (`nil`) on any
/// error — unknown pid, TCC denial, or a tap/aggregate/IOProc failure — after
/// rolling back whatever partial state was created. `stop()` is idempotent and
/// also runs on deinit, so a dropped engine never leaks CoreAudio objects.
@available(macOS 14.4, *)
final class ProcessTapEngine {
    private static let scratchCapacity = 4096

    private let ring: SampleRingBuffer
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var stopped = false

    init?(pid: Int, ring: SampleRingBuffer) {
        self.ring = ring

        guard let processObject = Self.processObject(for: pid) else { return nil }

        // The tap is private (invisible in Audio MIDI Setup) and keeps the
        // tapped app audible — the analyzer observes, never mutes.
        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr,
            tapID != AudioObjectID(kAudioObjectUnknown)
        else { return nil }

        // A tap only produces audio when read through an aggregate device that
        // lists it. The aggregate is private and auto-starts the tap.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "lyra-spectrum-tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]
        guard
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
                == noErr,
            aggregateID != AudioObjectID(kAudioObjectUnknown)
        else {
            rollBack()
            return nil
        }

        // The IO block runs on a real-time audio thread: no allocation, no
        // locks, no Swift concurrency. It mixes the first buffer down to mono
        // into a preallocated scratch and hands it to the wait-free ring.
        // `ring` and `scratch` are captured directly (not `self`) so CoreAudio
        // holding the block never retain-cycles the engine.
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: Self.scratchCapacity)
        scratch.initialize(repeating: 0, count: Self.scratchCapacity)
        self.scratch = scratch
        let capturedRing = ring
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) {
            _, inInputData, _, _, _ in
            Self.mixDownToMono(inInputData, into: scratch, ring: capturedRing)
        }
        guard status == noErr, let ioProcID, AudioDeviceStart(aggregateID, ioProcID) == noErr
        else {
            rollBack()
            return nil
        }
    }

    private var scratch: UnsafeMutablePointer<Float>?

    deinit {
        stop()
        scratch?.deallocate()
    }

    /// Tears the capture chain down in reverse order of construction.
    /// Idempotent — safe to call from both the owner and deinit.
    func stop() {
        guard !stopped else { return }
        stopped = true
        rollBack()
    }

    private func rollBack() {
        if let ioProcID, aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    /// Translates a pid into the CoreAudio process object required by
    /// `CATapDescription`. Returns `nil` for processes CoreAudio doesn't know
    /// (never launched audio, or no such pid).
    private static func processObject(for pid: Int) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processPid = pid_t(pid)
        var processObject = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &processPid) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), pidPointer,
                &size, &processObject
            )
        }
        guard status == noErr, processObject != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }
        return processObject
    }

    /// Real-time-safe mono mixdown of the first (interleaved) input buffer.
    private static func mixDownToMono(
        _ inputData: UnsafePointer<AudioBufferList>,
        into scratch: UnsafeMutablePointer<Float>,
        ring: SampleRingBuffer
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        guard let first = buffers.first, let data = first.mData else { return }
        let channels = max(Int(first.mNumberChannels), 1)
        let sampleCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let frames = min(sampleCount / channels, scratchCapacity)
        guard frames > 0 else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            let base = frame * channels
            let sum = (0..<channels).reduce(Float(0)) { $0 + samples[base + $1] }
            scratch[frame] = sum / Float(channels)
        }
        ring.write(scratch, count: frames)
    }
}
