import Dependencies

/// A write-only, always-on error sink. A caller reports that one operation failed and
/// says which subsystem it belongs to; the live implementation renders that as a line
/// on stderr. Like `DeveloperLog` this is a *StandardOutput-family* contract — an
/// output sink, never a DataStore: nothing reads it back as domain data.
///
/// It is deliberately separate from `DeveloperLog` (config-gated decision traces, file
/// output, contains listening history) and from `StandardOutput` (CLI results, which a
/// DataSource has no business reaching for). Sharing either would have made the three
/// purposes one switch.
///
/// The `lyra: ` prefix, the subsystem rendering, and the trailing newline all belong to
/// the implementation, so the convention lives in one place instead of being restated
/// at every call site as it was before #345.
public protocol ErrorLog: Sendable {
    /// Report one failed operation. `message` describes what failed and why, without
    /// the prefix or the subsystem — `"search failed: \(error)"`, not
    /// `"lyra: MusicBrainz search failed: \(error)"`.
    func record(_ subsystem: ErrorSubsystem, _ message: String)
}

public enum ErrorLogKey: TestDependencyKey {
    /// Silent under test: a suite that does not care about error reporting should not
    /// spray stderr, and one that does overrides `$0.errorLog` with a spy.
    public static let testValue: any ErrorLog = SilentErrorLog()
}

extension DependencyValues {
    public var errorLog: any ErrorLog {
        get { self[ErrorLogKey.self] }
        set { self[ErrorLogKey.self] = newValue }
    }
}

private struct SilentErrorLog: ErrorLog {
    func record(_ subsystem: ErrorSubsystem, _ message: String) {}
}
