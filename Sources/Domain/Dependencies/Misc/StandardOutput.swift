import Dependencies

/// A line-oriented output writer used by CLI commands.
/// Implementations must append a trailing newline after the message (`print` semantics).
/// Success messages go to stdout, failure messages go to stderr.
public protocol StandardOutput: Sendable {
    /// Writes `message` followed by a newline to stdout.
    func write(_ message: String)
    /// Writes `message` followed by a newline to stderr.
    func writeError(_ message: String)
    /// Encodes `value` as JSON and writes to stdout.
    func writeJson(_ value: some Encodable & Sendable)

    // MARK: - Typed output (Result)

    func write(_ result: StartResult)
    func write(_ result: StopResult)
    func write(_ result: ServiceInstallResult)
    func write(_ result: HealthCheckReport)
    func write(_ result: ServiceUninstallResult)
    func write(_ result: ConfigWriteResult)
    func write(_ result: ConfigPathResult)
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
    func writeError(_ message: String) { fatalError("StandardOutput.writeError not implemented") }
    func writeJson(_ value: some Encodable & Sendable) { fatalError("StandardOutput.writeJson not implemented") }
    func write(_ result: StartResult) { fatalError("StandardOutput.output not implemented") }
    func write(_ result: StopResult) { fatalError("StandardOutput.output not implemented") }
    func write(_ result: ServiceInstallResult) { fatalError("StandardOutput.output not implemented") }
    func write(_ result: ServiceUninstallResult) { fatalError("StandardOutput.output not implemented") }
    func write(_ result: ConfigWriteResult) { fatalError("StandardOutput.output not implemented") }
    func write(_ result: ConfigPathResult) { fatalError("StandardOutput.output not implemented") }
    func write(_ result: HealthCheckReport) { fatalError("StandardOutput.output not implemented") }
}
