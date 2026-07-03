/// Identity and audibility of the process that owns the now-playing session.
/// The spectrum analyzer uses it to scope its CoreAudio process tap to exactly
/// the audio source and to tear the tap down while playback is paused (#23).
public struct AudioSourceState {
    /// Process id of the now-playing app; `nil` when no app owns the session.
    public let pid: Int?
    /// `true` while audio is actually advancing (`playbackRate > 0`).
    public let isPlaying: Bool

    public init(pid: Int? = nil, isPlaying: Bool = false) {
        self.pid = pid
        self.isPlaying = isPlaying
    }
}

extension AudioSourceState: Sendable {}
extension AudioSourceState: Equatable {}
