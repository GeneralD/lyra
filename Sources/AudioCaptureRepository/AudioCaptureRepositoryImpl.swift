import Dependencies
import Domain

/// Repository over the CoreAudio process-tap DataSource (#23). Captured
/// audio has no cache layer, so orchestration is a thin forwarding of the
/// tap lifecycle and ring-buffer reads.
public struct AudioCaptureRepositoryImpl: Sendable {
    @Dependency(\.audioTapDataSource) private var dataSource

    public init() {}
}

extension AudioCaptureRepositoryImpl: AudioCaptureRepository {
    public func startCapture(pid: Int) async -> Bool {
        await dataSource.startTap(pid: pid)
    }

    public func stopCapture() async {
        await dataSource.stopTap()
    }

    public func latestSamples(count: Int) -> StereoSamples {
        dataSource.latestSamples(count: count)
    }
}
