import CoreAudio
import Dependencies
import Domain
import Testing

@testable import AudioTapDataSource

@Suite("LifecycleState.liveTapFormat")
struct LiveTapFormatTests {
    @Test("no tap yet (.empty) yields no format")
    func emptyYieldsNil() {
        guard #available(macOS 14.4, *) else { return }
        #expect(LifecycleState.empty.liveTapFormat == nil)
    }

    @Test("an unreadable tap object yields no format")
    func unreadableObjectYieldsNil() {
        guard #available(macOS 14.4, *) else { return }
        withDependencies {
            $0.audioTapGateway = StubAudioTapGateway(tapFormatResult: nil)
        } operation: {
            let state = LifecycleState.tapped(AudioObjectID(kAudioObjectUnknown))
            #expect(state.liveTapFormat == nil)
        }
    }

    @Test("a live tap's format is read through the gateway")
    func readableTapYieldsFormat() {
        guard #available(macOS 14.4, *) else { return }
        var format = AudioStreamBasicDescription()
        format.mSampleRate = 44100
        withDependencies {
            $0.audioTapGateway = StubAudioTapGateway(tapFormatResult: format)
        } operation: {
            let state = LifecycleState.tapped(AudioObjectID(10))
            #expect(state.liveTapFormat?.mSampleRate == 44100)
        }
    }
}

@Suite("LifecycleState.rolledBack")
struct LifecycleStateRolledBackTests {
    @Test("rolling back .empty destroys nothing and stays .empty")
    func emptyStaysEmpty() {
        guard #available(macOS 14.4, *) else { return }
        guard case .empty = LifecycleState.empty.rolledBack() else {
            Issue.record("expected .empty")
            return
        }
    }

    @Test("rolling back .tapped destroys only the tap")
    func tappedDestroysOnlyTheTap() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = SpyAudioTapGateway()
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            guard case .empty = LifecycleState.tapped(AudioObjectID(10)).rolledBack() else {
                Issue.record("expected .empty")
                return
            }
            #expect(gateway.callLog == ["destroyProcessTap"])
        }
    }

    @Test("rolling back .aggregated destroys the aggregate device then the tap")
    func aggregatedDestroysAggregateThenTap() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = SpyAudioTapGateway()
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            guard
                case .empty = LifecycleState.aggregated(AudioObjectID(10), AudioObjectID(20))
                    .rolledBack()
            else {
                Issue.record("expected .empty")
                return
            }
            #expect(gateway.callLog == ["destroyAggregateDevice", "destroyProcessTap"])
        }
    }

    @Test("rolling back .running stops the IOProc, then destroys it, the aggregate, and the tap")
    func runningTearsDownInFullReverseOrder() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = SpyAudioTapGateway()
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            guard
                case .empty = LifecycleState.running(
                    AudioObjectID(10), AudioObjectID(20), gateway.ioProcIDResult!
                ).rolledBack()
            else {
                Issue.record("expected .empty")
                return
            }
            #expect(
                gateway.callLog == [
                    "stop", "destroyIOProc", "destroyAggregateDevice", "destroyProcessTap",
                ])
        }
    }
}
