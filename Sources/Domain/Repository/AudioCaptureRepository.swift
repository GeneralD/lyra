import Dependencies

/// Access to the captured audio of the now-playing process (#23): capture
/// lifecycle plus the newest PCM window read.
public protocol AudioCaptureRepository: Sendable {
    /// Starts capturing the process's audio, replacing any active capture.
    /// Returns `false` when capture is unavailable.
    func startCapture(pid: Int) async -> Bool
    /// Tears down the active capture, if any. Safe to call repeatedly.
    func stopCapture() async
    /// The newest `count` captured mono samples, oldest first. Empty while
    /// no capture is active or before the buffer has filled once.
    func latestSamples(count: Int) -> [Float]
}

public enum AudioCaptureRepositoryKey: TestDependencyKey {
    public static let testValue: any AudioCaptureRepository = UnimplementedAudioCaptureRepository()
}

extension DependencyValues {
    public var audioCaptureRepository: any AudioCaptureRepository {
        get { self[AudioCaptureRepositoryKey.self] }
        set { self[AudioCaptureRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedAudioCaptureRepository: AudioCaptureRepository {
    func startCapture(pid: Int) async -> Bool { false }
    func stopCapture() async {}
    func latestSamples(count: Int) -> [Float] { [] }
}
