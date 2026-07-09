import CoreAudio
import Dependencies

/// Wraps the imperative CoreAudio calls that create and tear down a process
/// tap's capture chain (tap → aggregate device → IOProc). Mirrors
/// `ProcessGateway`'s OS-boundary role: injecting a fake makes
/// `ProcessTapEngine`'s call order, guard branching, and rollback logic
/// testable without live audio hardware.
public protocol AudioTapGateway: Sendable {
    /// Every CoreAudio process object currently on the system, unfiltered.
    /// The now-playing pid's subtree is matched against this list.
    func processObjects() -> [AudioObjectID]
    /// The owning pid of a CoreAudio process object, or `nil` when
    /// unreadable.
    func processPid(of object: AudioObjectID) -> pid_t?
    /// Creates the process tap described by `description`, or `nil` on
    /// failure.
    func createProcessTap(_ description: CATapDescription) -> AudioObjectID?
    /// The tap's output stream format read live via `kAudioTapPropertyFormat`,
    /// or `nil` when the read fails (e.g. an unknown object id).
    func tapFormat(of tapID: AudioObjectID) -> AudioStreamBasicDescription?
    /// Creates the aggregate device described by `description`, or `nil` on
    /// failure.
    func createAggregateDevice(_ description: [String: Any]) -> AudioObjectID?
    /// Registers `block` as the IOProc for `aggregateID`, or `nil` on
    /// failure.
    func createIOProc(
        aggregateID: AudioObjectID, block: @escaping AudioDeviceIOBlock
    ) -> AudioDeviceIOProcID?
    /// Starts IO on `aggregateID` through `ioProcID`. Returns whether it
    /// succeeded.
    func start(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) -> Bool
    func stop(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID)
    func destroyIOProc(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID)
    func destroyAggregateDevice(_ aggregateID: AudioObjectID)
    func destroyProcessTap(_ tapID: AudioObjectID)
}

public enum AudioTapGatewayKey: TestDependencyKey {
    public static let testValue: any AudioTapGateway = UnimplementedAudioTapGateway()
}

extension DependencyValues {
    public var audioTapGateway: any AudioTapGateway {
        get { self[AudioTapGatewayKey.self] }
        set { self[AudioTapGatewayKey.self] = newValue }
    }
}

private struct UnimplementedAudioTapGateway: AudioTapGateway {
    func processObjects() -> [AudioObjectID] {
        fatalError("AudioTapGateway.processObjects not implemented")
    }
    func processPid(of object: AudioObjectID) -> pid_t? {
        fatalError("AudioTapGateway.processPid not implemented")
    }
    func createProcessTap(_ description: CATapDescription) -> AudioObjectID? {
        fatalError("AudioTapGateway.createProcessTap not implemented")
    }
    func tapFormat(of tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        fatalError("AudioTapGateway.tapFormat not implemented")
    }
    func createAggregateDevice(_ description: [String: Any]) -> AudioObjectID? {
        fatalError("AudioTapGateway.createAggregateDevice not implemented")
    }
    func createIOProc(
        aggregateID: AudioObjectID, block: @escaping AudioDeviceIOBlock
    ) -> AudioDeviceIOProcID? {
        fatalError("AudioTapGateway.createIOProc not implemented")
    }
    func start(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) -> Bool {
        fatalError("AudioTapGateway.start not implemented")
    }
    func stop(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {
        fatalError("AudioTapGateway.stop not implemented")
    }
    func destroyIOProc(aggregateID: AudioObjectID, ioProcID: AudioDeviceIOProcID) {
        fatalError("AudioTapGateway.destroyIOProc not implemented")
    }
    func destroyAggregateDevice(_ aggregateID: AudioObjectID) {
        fatalError("AudioTapGateway.destroyAggregateDevice not implemented")
    }
    func destroyProcessTap(_ tapID: AudioObjectID) {
        fatalError("AudioTapGateway.destroyProcessTap not implemented")
    }
}
