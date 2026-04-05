import Dependencies

/// A line-oriented standard output writer used by CLI commands.
/// Implementations must append a trailing newline after the message (`print` semantics).
public protocol StandardOutput: Sendable {
    /// Writes `message` followed by a newline to standard output.
    func write(_ message: String)
}

public enum StandardOutputKey: TestDependencyKey {
    public static let testValue: any StandardOutput = UnimplementedStandardOutput()
}

extension DependencyValues {
    public var standardOutput: any StandardOutput {
        get { self[StandardOutputKey.self] }
        set { self[StandardOutputKey.self] = newValue }
    }
}

private struct UnimplementedStandardOutput: StandardOutput {
    func write(_ message: String) { fatalError("StandardOutput.write not implemented") }
}
