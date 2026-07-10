import CoreAudio
import Domain

/// Live `AudioTapGateway`: thin, 1:1 pass-through wrappers around the actual
/// CoreAudio C API calls. Holds no state of its own — `ProcessTapEngine`
/// keeps the object handles; this only performs the calls. Ungated like
/// `AudioTapDataSourceImpl`: only the process-tap create/destroy calls
/// require macOS 14.4+, so those two guard internally rather than gating the
/// whole type (aggregate device / IOProc are pre-existing CoreAudio HAL APIs).
public struct CoreAudioTapGateway {
    public init() {}
}

extension CoreAudioTapGateway: AudioTapGateway {
    public func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
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
        return objects
    }

    public func processPid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr,
            pid > 0
        else { return nil }
        return pid
    }

    public func createProcessTap(_ description: CATapDescription) -> AudioObjectID? {
        guard #available(macOS 14.4, *) else { return nil }
        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr,
            tapID != AudioObjectID(kAudioObjectUnknown)
        else { return nil }
        return tapID
    }

    public func tapFormat(of tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr
        else { return nil }
        return format
    }

    public func createAggregateDevice(_ description: [String: Any]) -> AudioObjectID? {
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        guard
            AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
                == noErr,
            aggregateID != AudioObjectID(kAudioObjectUnknown)
        else { return nil }
        return aggregateID
    }

    public func createIOProc(
        aggregateID: AudioObjectID, block: @escaping AudioDeviceIOBlock
    ) -> AudioDeviceIOProcID? {
        var ioProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil, block)
        guard status == noErr, let ioProcID else { return nil }
        return ioProcID
    }

    public func start(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) -> Bool {
        AudioDeviceStart(aggregateID, ioProcID) == noErr
    }

    public func stop(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {
        AudioDeviceStop(aggregateID, ioProcID)
    }

    public func destroyIOProc(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {
        AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
    }

    public func destroyAggregateDevice(_ aggregateID: AudioObjectID) {
        AudioHardwareDestroyAggregateDevice(aggregateID)
    }

    public func destroyProcessTap(_ tapID: AudioObjectID) {
        guard #available(macOS 14.4, *) else { return }
        AudioHardwareDestroyProcessTap(tapID)
    }
}
