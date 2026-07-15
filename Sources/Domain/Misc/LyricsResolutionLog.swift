import Dependencies

/// Sink for the lyrics-resolution decision trace (#331). The Repository builds a
/// human-readable block per resolution and hands it here; the live implementation
/// appends it to a config-gated file, and does nothing when the trace is disabled.
public protocol LyricsResolutionLog: Sendable {
    /// Whether the trace is turned on. Callers gate the (cheap) trace-string building
    /// on this so a disabled log costs nothing on the resolution path.
    var isEnabled: Bool { get }
    /// Append one resolution's trace block. No-op when disabled.
    func record(_ text: String)
}

public enum LyricsResolutionLogKey: TestDependencyKey {
    /// Disabled by default so tests neither build nor emit traces unless they
    /// override `$0.lyricsResolutionLog` explicitly.
    public static let testValue: any LyricsResolutionLog = DisabledLyricsResolutionLog()
}

extension DependencyValues {
    public var lyricsResolutionLog: any LyricsResolutionLog {
        get { self[LyricsResolutionLogKey.self] }
        set { self[LyricsResolutionLogKey.self] = newValue }
    }
}

private struct DisabledLyricsResolutionLog: LyricsResolutionLog {
    var isEnabled: Bool { false }
    func record(_ text: String) {}
}
