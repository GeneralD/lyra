import Dependencies

/// Captures one process's audio output through a CoreAudio process tap and
/// exposes the newest PCM window for spectrum analysis (#23).
public protocol AudioTapDataSource: Sendable {
    /// Starts capturing the process's audio output, replacing any active tap.
    /// Returns `false` when tapping is unavailable — host below the macOS 14.4
    /// floor, TCC permission denied, unknown process, or a CoreAudio error.
    func startTap(pid: Int) async -> Bool
    /// Tears down the active tap, if any. Safe to call repeatedly.
    func stopTap() async
    /// The newest `count` captured samples per channel, oldest first. Both
    /// channels are empty while no tap is active or before the capture
    /// buffer has filled once.
    func latestSamples(count: Int) -> StereoSamples
}

public enum AudioTapDataSourceKey: TestDependencyKey {
    public static let testValue: any AudioTapDataSource = UnimplementedAudioTapDataSource()
}

extension DependencyValues {
    public var audioTapDataSource: any AudioTapDataSource {
        get { self[AudioTapDataSourceKey.self] }
        set { self[AudioTapDataSourceKey.self] = newValue }
    }
}

private struct UnimplementedAudioTapDataSource: AudioTapDataSource {
    func startTap(pid: Int) async -> Bool { false }
    func stopTap() async {}
    func latestSamples(count: Int) -> StereoSamples { StereoSamples() }
}
