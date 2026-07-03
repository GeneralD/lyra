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

        let processObjects = Self.processObjects(forSubtreeOf: pid)
        guard !processObjects.isEmpty else { return nil }

        // The tap is private (invisible in Audio MIDI Setup) and keeps the
        // tapped app audible — the analyzer observes, never mutes.
        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
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

    /// CoreAudio process objects for `pid` and every descendant process.
    /// The now-playing pid alone is not enough: browsers (Chromium-based)
    /// emit audio from a helper subprocess, so a tap scoped to the main pid
    /// captures silence. Covering the whole subtree taps whichever family
    /// member actually owns the audio stream.
    private static func processObjects(forSubtreeOf pid: Int) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var objects = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects)
                == noErr
        else { return [] }
        return objects.filter { isInSubtree(processPid(of: $0), root: pid_t(pid)) }
    }

    /// The owning pid of a CoreAudio process object, or `nil` when unreadable.
    private static func processPid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr,
            pid > 0
        else { return nil }
        return pid
    }

    /// Whether `pid` equals `root` or has `root` among its ancestors.
    private static func isInSubtree(_ pid: pid_t?, root: pid_t) -> Bool {
        guard var current = pid else { return false }
        while current > 1 {
            guard current != root else { return true }
            var info = proc_bsdinfo()
            let read = proc_pidinfo(
                current, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            guard read == Int32(MemoryLayout<proc_bsdinfo>.size) else { return false }
            current = pid_t(info.pbi_ppid)
        }
        return false
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
