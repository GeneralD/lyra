import Dependencies

/// A line-oriented standard output writer used by CLI commands.
/// Implementations must append a trailing newline after the message (`print` semantics).
public protocol StandardOutput: Sendable {
    /// Writes `message` followed by a newline to standard output.
    func write(_ message: String)

    // MARK: - Typed output

    func output(_ result: StartSuccess)
    func output(_ error: StartFailure)
    func output(_ result: StopSuccess)
    func output(_ error: StopFailure)
    func output(_ result: ServiceInstallSuccess)
    func output(_ error: ServiceInstallFailure)
    func output(_ result: ServiceUninstallSuccess)
    func output(_ error: ServiceUninstallFailure)
    func output(_ result: ConfigWriteSuccess)
    func output(_ result: ConfigPathSuccess)
    func output(_ error: ConfigFailure)
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
    func output(_ result: StartSuccess) { fatalError("StandardOutput.output not implemented") }
    func output(_ error: StartFailure) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: StopSuccess) { fatalError("StandardOutput.output not implemented") }
    func output(_ error: StopFailure) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: ServiceInstallSuccess) { fatalError("StandardOutput.output not implemented") }
    func output(_ error: ServiceInstallFailure) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: ServiceUninstallSuccess) { fatalError("StandardOutput.output not implemented") }
    func output(_ error: ServiceUninstallFailure) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: ConfigWriteSuccess) { fatalError("StandardOutput.output not implemented") }
    func output(_ result: ConfigPathSuccess) { fatalError("StandardOutput.output not implemented") }
    func output(_ error: ConfigFailure) { fatalError("StandardOutput.output not implemented") }
}
