import Dependencies

/// A stoppable watch handle.
///
/// `stop()` does not synchronously wait out an in-flight change callback: a
/// callback racing with `stop()` may still be delivered after it returns.
/// Waiting would invert the lock order between the watch session and its
/// consumer and deadlock, so consumers instead gate delivered events on their
/// own teardown state (as `ConfigInteractorImpl.applyReload` does).
public protocol ConfigWatchToken: Sendable {
    func stop()
}

/// An OS boundary that watches directories and files, calling `onChange` for each change.
/// Consumed by the ConfigDataSource layer — which owns watch-target resolution — mirroring
/// how AudioTapDataSource consumes AudioTapGateway. The live implementation uses
/// DispatchSource and supports fake injection for testing.
public protocol ConfigWatchGateway: Sendable {
    /// Starts watching `directory` and calls `onChange` on an arbitrary queue for each event.
    /// Returns nil when a watch cannot be established.
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)?

    /// Starts watching the file itself and calls `onChange` on an arbitrary queue for each event.
    /// A directory watch alone only observes entry changes (rename/create/delete), so in-place
    /// overwrites — editors that save without renaming, `cp` onto an existing file, appends —
    /// are invisible to it; this file-level watch covers them. Returns nil when the file cannot
    /// be opened (e.g. it does not exist yet).
    func watch(file: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)?
}

public enum ConfigWatchGatewayKey: TestDependencyKey {
    public static let testValue: any ConfigWatchGateway = UnimplementedConfigWatchGateway()
}

extension DependencyValues {
    public var configWatchGateway: any ConfigWatchGateway {
        get { self[ConfigWatchGatewayKey.self] }
        set { self[ConfigWatchGatewayKey.self] = newValue }
    }
}

private struct UnimplementedConfigWatchGateway: ConfigWatchGateway {
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? { nil }
    func watch(file: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? { nil }
}
