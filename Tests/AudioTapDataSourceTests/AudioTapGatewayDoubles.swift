import CoreAudio
import Domain

@testable import AudioTapDataSource

/// No-capture C function pointer matching `AudioDeviceIOProc`'s signature —
/// stands in for a real registered IOProc handle in test doubles.
private func stubIOProc(
    _: AudioObjectID,
    _: UnsafePointer<AudioTimeStamp>,
    _: UnsafePointer<AudioBufferList>,
    _: UnsafePointer<AudioTimeStamp>,
    _: UnsafeMutablePointer<AudioBufferList>,
    _: UnsafePointer<AudioTimeStamp>,
    _: UnsafeMutableRawPointer?
) -> OSStatus { noErr }

/// Invokes an `AudioDeviceIOBlock` with a synthesized 2-channel interleaved
/// buffer, standing in for a real-time IOProc firing — so a test can drive
/// `ProcessTapEngine`'s registered block without a live audio thread.
func invokeIOBlock(_ block: AudioDeviceIOBlock, interleavedSamples: [Float]) {
    var samples = interleavedSamples
    samples.withUnsafeMutableBufferPointer { buf in
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 2,
                mDataByteSize: UInt32(buf.count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(buf.baseAddress)))
        var timeStamp = AudioTimeStamp()
        var outputData = AudioBufferList()
        withUnsafeMutablePointer(to: &bufferList) { inputPtr in
            withUnsafeMutablePointer(to: &outputData) { outputPtr in
                withUnsafePointer(to: &timeStamp) { timeStampPtr in
                    block(timeStampPtr, UnsafePointer(inputPtr), timeStampPtr, outputPtr, timeStampPtr)
                }
            }
        }
    }
}

/// Configurable fake `AudioTapGateway` (#310) — every call returns a fixed,
/// injected result. Use `SpyAudioTapGateway` instead when a test needs to
/// assert which calls were made or in what order.
struct StubAudioTapGateway: AudioTapGateway {
    var processObjectsResult: [AudioObjectID] = []
    var processPidResult: pid_t?
    var tapIDResult: AudioObjectID?
    var tapFormatResult: AudioStreamBasicDescription?
    var aggregateIDResult: AudioObjectID?
    var ioProcIDResult: AudioDeviceIOProcID?
    var startResult = false

    func processObjects() -> [AudioObjectID] { processObjectsResult }
    func processPid(of object: AudioObjectID) -> pid_t? { processPidResult }
    func createProcessTap(_ description: CATapDescription) -> AudioObjectID? { tapIDResult }
    func tapFormat(of tapID: AudioObjectID) -> AudioStreamBasicDescription? { tapFormatResult }
    func createAggregateDevice(_ description: [String: Any]) -> AudioObjectID? { aggregateIDResult }
    func createIOProc(
        aggregateID: AudioObjectID, block: @escaping AudioDeviceIOBlock
    ) -> AudioDeviceIOProcID? { ioProcIDResult }
    func start(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) -> Bool { startResult }
    func stop(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {}
    func destroyIOProc(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {}
    func destroyAggregateDevice(_ aggregateID: AudioObjectID) {}
    func destroyProcessTap(_ tapID: AudioObjectID) {}
}

extension StubAudioTapGateway {
    /// `ioProcIDResult` pre-filled with a valid stand-in handle — convenience
    /// for tests that need `createIOProc` to succeed without caring which
    /// function pointer it returns.
    static var withValidIOProc: StubAudioTapGateway {
        var gateway = StubAudioTapGateway()
        gateway.ioProcIDResult = stubIOProc
        return gateway
    }
}

/// Records every call `ProcessTapEngine`/`LifecycleState` makes, so tests can
/// assert both the returned handles and the exact create/destroy sequence
/// (e.g. rollback order).
final class SpyAudioTapGateway: AudioTapGateway, @unchecked Sendable {
    private(set) var callLog: [String] = []

    func resetLog() { callLog.removeAll() }

    var processObjectsResult: [AudioObjectID] = []
    var processPidResult: pid_t?
    var tapIDResult: AudioObjectID?
    var tapFormatResult: AudioStreamBasicDescription?
    var aggregateIDResult: AudioObjectID?
    var ioProcIDResult: AudioDeviceIOProcID? = stubIOProc
    var startResult = false
    /// When set, `createIOProc` immediately fires the registered block with
    /// these interleaved samples, simulating a real-time IOProc callback.
    var fireIOBlockWithInterleavedSamples: [Float]?

    func processObjects() -> [AudioObjectID] { processObjectsResult }
    func processPid(of object: AudioObjectID) -> pid_t? { processPidResult }

    func createProcessTap(_ description: CATapDescription) -> AudioObjectID? {
        callLog.append("createProcessTap")
        return tapIDResult
    }

    func tapFormat(of tapID: AudioObjectID) -> AudioStreamBasicDescription? { tapFormatResult }

    func createAggregateDevice(_ description: [String: Any]) -> AudioObjectID? {
        callLog.append("createAggregateDevice")
        return aggregateIDResult
    }

    func createIOProc(
        aggregateID: AudioObjectID, block: @escaping AudioDeviceIOBlock
    ) -> AudioDeviceIOProcID? {
        callLog.append("createIOProc")
        if let samples = fireIOBlockWithInterleavedSamples {
            invokeIOBlock(block, interleavedSamples: samples)
        }
        return ioProcIDResult
    }

    func start(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) -> Bool {
        callLog.append("start")
        return startResult
    }

    func stop(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {
        callLog.append("stop")
    }

    func destroyIOProc(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {
        callLog.append("destroyIOProc")
    }

    func destroyAggregateDevice(_ aggregateID: AudioObjectID) {
        callLog.append("destroyAggregateDevice")
    }

    func destroyProcessTap(_ tapID: AudioObjectID) {
        callLog.append("destroyProcessTap")
    }
}
