import CoreAudio
import Dependencies
import Domain
import Testing

@testable import AudioTapDataSource

@Suite("ProcessTapEngine.init?")
struct ProcessTapEngineInitTests {
    private let pid = 12345

    private func rings() -> (SampleRingBuffer, SampleRingBuffer) {
        (SampleRingBuffer(capacity: 8), SampleRingBuffer(capacity: 8))
    }

    /// A gateway pre-configured so the process-subtree gate passes: it
    /// reports one process object whose pid equals the engine's own root
    /// pid, which `isInProcessSubtree` matches on the very first check.
    private func subtreeMatchedGateway() -> SpyAudioTapGateway {
        let gateway = SpyAudioTapGateway()
        gateway.processObjectsResult = [AudioObjectID(1)]
        gateway.processPidResult = pid_t(pid)
        return gateway
    }

    private func format(rate: Double) -> AudioStreamBasicDescription {
        var f = AudioStreamBasicDescription()
        f.mSampleRate = rate
        return f
    }

    @Test("no matching process object in the subtree fails before any tap call")
    func emptySubtreeFailsEarly() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = SpyAudioTapGateway()  // processObjectsResult defaults to []
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            let (left, right) = rings()
            #expect(ProcessTapEngine(pid: pid, leftRing: left, rightRing: right) == nil)
            #expect(gateway.callLog.isEmpty)
        }
    }

    @Test("a failed process tap creation fails init without touching rollback")
    func createProcessTapFailureFailsInit() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = subtreeMatchedGateway()
        gateway.tapIDResult = nil
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            let (left, right) = rings()
            #expect(ProcessTapEngine(pid: pid, leftRing: left, rightRing: right) == nil)
            #expect(gateway.callLog == ["createProcessTap"])
        }
    }

    @Test("a failed aggregate device creation rolls back the tap")
    func createAggregateDeviceFailureRollsBackTap() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = subtreeMatchedGateway()
        gateway.tapIDResult = AudioObjectID(10)
        gateway.aggregateIDResult = nil
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            let (left, right) = rings()
            #expect(ProcessTapEngine(pid: pid, leftRing: left, rightRing: right) == nil)
            #expect(
                gateway.callLog == ["createProcessTap", "createAggregateDevice", "destroyProcessTap"])
        }
    }

    @Test("a failed IOProc creation rolls back the aggregate device and tap")
    func createIOProcFailureRollsBackAggregateAndTap() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = subtreeMatchedGateway()
        gateway.tapIDResult = AudioObjectID(10)
        gateway.aggregateIDResult = AudioObjectID(20)
        gateway.ioProcIDResult = nil
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            let (left, right) = rings()
            #expect(ProcessTapEngine(pid: pid, leftRing: left, rightRing: right) == nil)
            #expect(
                gateway.callLog == [
                    "createProcessTap", "createAggregateDevice", "createIOProc",
                    "destroyAggregateDevice", "destroyProcessTap",
                ])
        }
    }

    @Test("a failed start rolls back the aggregate device and tap, but not the IOProc")
    func startFailureRollsBackAggregateAndTapOnly() {
        guard #available(macOS 14.4, *) else { return }
        // Mirrors the pre-#310 behavior: `state` only reaches `.aggregated`
        // before the start guard, so the created (but never-registered)
        // IOProc handle is never explicitly destroyed — the OS reclaims it
        // when the owning aggregate device is torn down.
        let gateway = subtreeMatchedGateway()
        gateway.tapIDResult = AudioObjectID(10)
        gateway.aggregateIDResult = AudioObjectID(20)
        gateway.startResult = false
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            let (left, right) = rings()
            #expect(ProcessTapEngine(pid: pid, leftRing: left, rightRing: right) == nil)
            #expect(
                gateway.callLog == [
                    "createProcessTap", "createAggregateDevice", "createIOProc", "start",
                    "destroyAggregateDevice", "destroyProcessTap",
                ])
        }
    }

    @Test("a fully successful chain returns a live engine tagged with the tap's sample rate")
    func fullSuccessReturnsLiveEngine() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = subtreeMatchedGateway()
        gateway.tapIDResult = AudioObjectID(10)
        gateway.tapFormatResult = format(rate: 44100)
        gateway.aggregateIDResult = AudioObjectID(20)
        gateway.startResult = true
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            let (left, right) = rings()
            let engine = ProcessTapEngine(pid: pid, leftRing: left, rightRing: right)
            #expect(engine?.sampleRate == 44100)
            #expect(
                gateway.callLog == [
                    "createProcessTap", "createAggregateDevice", "createIOProc", "start",
                ])
        }
    }

    @Test("an unreadable tap format falls back to the 48 kHz mixdown default")
    func unreadableFormatFallsBackTo48k() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = subtreeMatchedGateway()
        gateway.tapIDResult = AudioObjectID(10)
        gateway.tapFormatResult = nil
        gateway.aggregateIDResult = AudioObjectID(20)
        gateway.startResult = true
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            let (left, right) = rings()
            let engine = ProcessTapEngine(pid: pid, leftRing: left, rightRing: right)
            #expect(engine?.sampleRate == 48000)
        }
    }

    @Test("the registered IOProc block deinterleaves samples into the caller's rings")
    func ioProcBlockDeinterleavesIntoRings() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = subtreeMatchedGateway()
        gateway.tapIDResult = AudioObjectID(10)
        gateway.aggregateIDResult = AudioObjectID(20)
        gateway.startResult = true
        // Interleaved L R L R — fired synchronously the moment the engine
        // registers the block, standing in for a real-time IOProc callback.
        gateway.fireIOBlockWithInterleavedSamples = [1, -1, 2, -2]
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            let (left, right) = rings()
            let engine = ProcessTapEngine(pid: pid, leftRing: left, rightRing: right)
            #expect(engine != nil)
            #expect(left.latest(2) == [1, 2])
            #expect(right.latest(2) == [-1, -2])
        }
    }

    @Test("stop() after a successful init tears everything down in reverse order")
    func stopTearsDownInReverseOrder() {
        guard #available(macOS 14.4, *) else { return }
        let gateway = subtreeMatchedGateway()
        gateway.tapIDResult = AudioObjectID(10)
        gateway.aggregateIDResult = AudioObjectID(20)
        gateway.startResult = true
        withDependencies {
            $0.audioTapGateway = gateway
        } operation: {
            let (left, right) = rings()
            let engine = ProcessTapEngine(pid: pid, leftRing: left, rightRing: right)
            #expect(engine != nil)
            gateway.resetLog()
            engine?.stop()
            #expect(
                gateway.callLog == ["stop", "destroyIOProc", "destroyAggregateDevice", "destroyProcessTap"]
            )
            // Idempotent: a second stop on the now-.empty state destroys nothing.
            engine?.stop()
            #expect(
                gateway.callLog == ["stop", "destroyIOProc", "destroyAggregateDevice", "destroyProcessTap"]
            )
        }
    }
}
