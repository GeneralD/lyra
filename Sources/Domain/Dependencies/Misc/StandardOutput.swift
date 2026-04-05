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

    func output(_ result: StartResult)
    func output(_ result: StopResult)
    func output(_ result: ServiceInstallResult)
    func output(_ result: HealthCheckReport)
    func output(_ result: ServiceUninstallResult)
    func output(_ result: ConfigWriteResult)
    func output(_ result: ConfigPathResult)
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
    func output(_ result: StartResult) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: StopResult) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: ServiceInstallResult) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: ServiceUninstallResult) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: ConfigWriteResult) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: ConfigPathResult) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: HealthCheckReport) { fatalError("StandardOutput.output not implemented") }
}
