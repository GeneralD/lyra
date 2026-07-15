import Dependencies

/// A stoppable watch handle.
public protocol ConfigWatchToken: Sendable {
    func stop()
}

/// An OS boundary that watches the config directory and calls `onChange` for each change.
/// The live implementation uses DispatchSource and supports fake injection for testing,
/// following the same boundary justification as AudioTapGateway.
public protocol ConfigWatchGateway: Sendable {
    /// Starts watching `directory` and calls `onChange` on an arbitrary queue for each event.
    /// Returns nil when a watch cannot be established.
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)?
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
}
