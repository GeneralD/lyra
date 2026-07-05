import Entity
import Testing

@testable import AudioTapDataSource

/// Fake tap standing in for the CoreAudio-backed `ProcessTapEngine`, so the
/// start/stop and sample-rate tagging paths run without a live audio device.
private final class FakeTapEngine: AudioTapEngine, @unchecked Sendable {
    let sampleRate: Double
    private(set) var stopCount = 0
    init(sampleRate: Double) { self.sampleRate = sampleRate }
    func stop() { stopCount += 1 }
}

@Suite("AudioTapDataSourceImpl")
struct AudioTapDataSourceImplTests {
    @Test("latestSamples is empty while no tap is active")
    func emptyWithoutTap() {
        let dataSource = AudioTapDataSourceImpl()
        #expect(dataSource.latestSamples(count: 1024) == StereoSamples())
    }

    @Test("latestSamples tags the window with the active tap's sample rate")
    func tagsWindowWithTapRate() async {
        let tap = FakeTapEngine(sampleRate: 44100)
        let dataSource = AudioTapDataSourceImpl(makeEngine: { _, _, _ in tap })
        #expect(await dataSource.startTap(pid: 1234))
        // A live tap is present, so the window carries its real rate (#299)
        // rather than the empty-window default.
        #expect(dataSource.latestSamples(count: 1024).sampleRate == 44100)
    }

    @Test("startTap stops the previous tap before swapping in the new one")
    func restartStopsPreviousTap() async {
        let first = FakeTapEngine(sampleRate: 48000)
        let second = FakeTapEngine(sampleRate: 44100)
        let dataSource = AudioTapDataSourceImpl(makeEngine: { pid, _, _ in pid == 1 ? first : second })
        #expect(await dataSource.startTap(pid: 1))
        #expect(await dataSource.startTap(pid: 2))
        // The first tap is torn down exactly once, and the window now follows
        // the second tap's rate.
        #expect(first.stopCount == 1)
        #expect(dataSource.latestSamples(count: 1024).sampleRate == 44100)
    }

    @Test("startTap reports failure and stays tapless when the factory yields nothing")
    func startFailsWhenFactoryReturnsNil() async {
        let dataSource = AudioTapDataSourceImpl(makeEngine: { _, _, _ in nil })
        #expect(await dataSource.startTap(pid: 1) == false)
        #expect(dataSource.latestSamples(count: 1024) == StereoSamples())
    }

    @Test("stopTap tears the active tap down and clears it")
    func stopTearsActiveTapDown() async {
        let tap = FakeTapEngine(sampleRate: 48000)
        let dataSource = AudioTapDataSourceImpl(makeEngine: { _, _, _ in tap })
        #expect(await dataSource.startTap(pid: 1))
        await dataSource.stopTap()
        #expect(tap.stopCount == 1)
        #expect(dataSource.latestSamples(count: 1024) == StereoSamples())
    }

    @Test("startTap fails for a pid CoreAudio does not know")
    func unknownPidFails() async {
        let dataSource = AudioTapDataSourceImpl()
        // A pid far beyond pid_max never has a CoreAudio process object, so
        // the translation step fails before any tap (or TCC prompt) is created.
        #expect(await dataSource.startTap(pid: 99_999_999) == false)
        #expect(dataSource.latestSamples(count: 1024) == StereoSamples())
    }

    @Test("stopTap without a tap is a safe no-op, repeatedly")
    func stopIsIdempotent() async {
        let dataSource = AudioTapDataSourceImpl()
        await dataSource.stopTap()
        await dataSource.stopTap()
        #expect(dataSource.latestSamples(count: 1024) == StereoSamples())
    }
}
