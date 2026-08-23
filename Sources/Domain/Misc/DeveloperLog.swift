import Dependencies

/// A write-only, config-gated developer/diagnostic sink. A caller builds a
/// human-readable block and hands it here; the live implementation appends it to
/// a file, and does nothing when the sink is disabled. This is a *general* contract
/// (StandardOutput family — an output sink, never a DataStore: nothing reads it back
/// as domain data); each purpose gets its own DI instance rather than one shared log.
public protocol DeveloperLog: Sendable {
    /// Whether the sink is turned on. Callers gate the (cheap) trace-string building
    /// on this so a disabled sink costs nothing on the hot path.
    var isEnabled: Bool { get }
    /// Append one block. No-op when disabled.
    func record(_ text: String)
}

/// The lyrics-resolution decision-trace instance (#331). A general `DeveloperLog`,
/// wired to the `[developer] lyrics_resolution` toggle; a future trace (e.g. wallpaper
/// resolution) adds its own key rather than sharing this one.
public enum LyricsResolutionLogKey: TestDependencyKey {
    /// Disabled by default so tests neither build nor emit traces unless they
    /// override `$0.lyricsResolutionLog` explicitly.
    public static let testValue: any DeveloperLog = DisabledDeveloperLog()
}

extension DependencyValues {
    public var lyricsResolutionLog: any DeveloperLog {
        get { self[LyricsResolutionLogKey.self] }
        set { self[LyricsResolutionLogKey.self] = newValue }
    }
}

private struct DisabledDeveloperLog: DeveloperLog {
    var isEnabled: Bool { false }
    func record(_ text: String) {}
}
