import Entity
import Testing

@testable import AudioTapDataSource

@Suite("AudioTapDataSourceImpl")
struct AudioTapDataSourceImplTests {
    @Test("latestSamples is empty while no tap is active")
    func emptyWithoutTap() {
        let dataSource = AudioTapDataSourceImpl()
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
