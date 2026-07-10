import CoreAudio
import Dependencies
import Domain

/// What CoreAudio objects a `ProcessTapEngine` currently owns, in the order
/// construction acquires them. Each case carries exactly the handles that
/// exist at that point, so a state combination that should never occur (an
/// aggregate device without its tap, an IOProc without its aggregate) has no
/// representation to begin with.
@available(macOS 14.4, *)
enum LifecycleState {
    case empty
    case tapped(AudioObjectID)
    case aggregated(AudioObjectID, AudioObjectID)
    case running(AudioObjectID, AudioObjectID, AudioDeviceIOProcID)

    private var tapID: AudioObjectID? {
        switch self {
        case .empty: return nil
        case .tapped(let tapID), .aggregated(let tapID, _), .running(let tapID, _, _):
            return tapID
        }
    }

    /// The tap's output stream format read live via `kAudioTapPropertyFormat`,
    /// or `nil` when this state holds no tap yet, or when the read fails
    /// (e.g. an unknown object id). Routed through the injected
    /// `AudioTapGateway` (#310) so this branch is testable with a fake tap.
    var liveTapFormat: AudioStreamBasicDescription? {
        @Dependency(\.audioTapGateway) var gateway
        guard let tapID else { return nil }
        return gateway.tapFormat(of: tapID)
    }

    /// Tears down whatever this state currently holds, in reverse order of
    /// acquisition, and returns the resulting `.empty` state. Destroys
    /// nothing when already `.empty`, which is what makes repeated rollback
    /// safe without a separate "already stopped" flag. Routed through the
    /// injected `AudioTapGateway` (#310) so every non-empty branch is
    /// testable with a fake gateway, without live audio hardware.
    func rolledBack() -> LifecycleState {
        @Dependency(\.audioTapGateway) var gateway
        switch self {
        case .empty:
            break
        case .tapped(let tapID):
            gateway.destroyProcessTap(tapID)
        case .aggregated(let tapID, let aggregateID):
            gateway.destroyAggregateDevice(aggregateID)
            gateway.destroyProcessTap(tapID)
        case .running(let tapID, let aggregateID, let ioProcID):
            gateway.stop(aggregateID: aggregateID, ioProcID: ioProcID)
            gateway.destroyIOProc(aggregateID: aggregateID, ioProcID: ioProcID)
            gateway.destroyAggregateDevice(aggregateID)
            gateway.destroyProcessTap(tapID)
        }
        return .empty
    }
}
