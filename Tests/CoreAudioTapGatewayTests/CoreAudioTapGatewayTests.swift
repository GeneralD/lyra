import CoreAudio
import CoreAudioTapGateway
import Foundation
import Testing

/// CI-runnable smoke tests for the live CoreAudio pass-through (#315).
///
/// Every wrapper is guard-based, so exercising each call covers its lines
/// even when the HAL refuses the operation. Environment-dependent steps
/// (aggregate device creation on a headless runner) tolerate `nil` instead
/// of asserting success — the untestable residue is the process-tap happy
/// path, which needs the System Audio Recording TCC grant plus a live audio
/// source and stays out of scope here.
@Suite("CoreAudioTapGateway")
struct CoreAudioTapGatewayTests {
    private let gateway = CoreAudioTapGateway()
    private let invalid = AudioObjectID(kAudioObjectUnknown)

    @Test("invalid object IDs take the guard path and return nil")
    func invalidObjectIDsReturnNil() {
        #expect(gateway.processPid(of: invalid) == nil)
        #expect(gateway.tapFormat(of: invalid) == nil)
        #expect(gateway.createIOProc(aggregateID: invalid, block: { _, _, _, _, _ in }) == nil)
    }

    @Test("destroy calls on invalid IDs are safely ignored")
    func destroyOnInvalidIDsIsIgnored() {
        gateway.destroyAggregateDevice(invalid)
        gateway.destroyProcessTap(invalid)
    }

    @Test("processObjects queries the HAL and resolves pids without TCC")
    func processObjectsResolvePids() {
        let objects = gateway.processObjects()
        #expect(objects.allSatisfy { $0 != invalid })
        let pids = objects.compactMap(gateway.processPid(of:))
        #expect(pids.allSatisfy { $0 > 0 })
    }

    @Test("aggregate device round-trip: create → IOProc → start/stop → destroy")
    func aggregateDeviceRoundTrip() {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "lyra-test-aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
        ]
        guard let aggregateID = gateway.createAggregateDevice(description) else { return }
        defer { gateway.destroyAggregateDevice(aggregateID) }
        guard
            let ioProcID = gateway.createIOProc(
                aggregateID: aggregateID, block: { _, _, _, _, _ in })
        else { return }
        defer { gateway.destroyIOProc(aggregateID: aggregateID, ioProcID: ioProcID) }
        guard gateway.start(aggregateID: aggregateID, ioProcID: ioProcID) else { return }
        gateway.stop(aggregateID: aggregateID, ioProcID: ioProcID)
    }

    @Test("createProcessTap without a TCC grant takes the guard path")
    func processTapWithoutPermission() {
        // Creating a process tap can raise the System Audio Recording TCC
        // prompt on a developer machine, so this runs only on CI, where the
        // unattended denial exercises the error → nil guard path.
        guard ProcessInfo.processInfo.environment["CI"] != nil else { return }
        guard #available(macOS 14.4, *) else { return }
        guard
            let tapID = gateway.createProcessTap(
                CATapDescription(stereoMixdownOfProcesses: []))
        else { return }
        _ = gateway.tapFormat(of: tapID)
        gateway.destroyProcessTap(tapID)
    }
}
