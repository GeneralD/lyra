import Darwin.POSIX
import Domain
import Foundation

public struct PrintStandardOutput: StandardOutput {
    private let stdoutPrinter: @Sendable (String, String) -> Void
    private let stderrPrinter: @Sendable (String) -> Void
    private let stdoutFlusher: @Sendable () -> Void
    private let terminalColumnsProvider: @Sendable () -> Int
    private let echoSetter: @Sendable (Bool) -> Void

    public init() {
        self.stdoutPrinter = { message, terminator in
            print(message, terminator: terminator)
        }
        self.stderrPrinter = { message in
            fputs(message, stderr)
        }
        self.stdoutFlusher = {
            fflush(stdout)
        }
        self.terminalColumnsProvider = {
            guard isatty(STDOUT_FILENO) != 0 else { return 80 }
            var ws = winsize()
            guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 else { return 80 }
            return Int(ws.ws_col)
        }
        self.echoSetter = { enabled in
            guard isatty(STDIN_FILENO) != 0 else { return }
            var attr = termios()
            guard tcgetattr(STDIN_FILENO, &attr) == 0 else { return }
            if enabled {
                attr.c_lflag |= UInt(ECHO | ICANON)
            } else {
                attr.c_lflag &= ~UInt(ECHO | ICANON)
            }
            tcsetattr(STDIN_FILENO, TCSANOW, &attr)
        }
    }

    init(
        stdoutPrinter: @escaping @Sendable (String, String) -> Void,
        stderrPrinter: @escaping @Sendable (String) -> Void,
        stdoutFlusher: @escaping @Sendable () -> Void,
        terminalColumnsProvider: @escaping @Sendable () -> Int,
        echoSetter: @escaping @Sendable (Bool) -> Void
    ) {
        self.stdoutPrinter = stdoutPrinter
        self.stderrPrinter = stderrPrinter
        self.stdoutFlusher = stdoutFlusher
        self.terminalColumnsProvider = terminalColumnsProvider
        self.echoSetter = echoSetter
    }

    public func write(_ message: String) { stdoutPrinter(message, "\n") }
    public func writeError(_ message: String) { stderrPrinter(message + "\n") }

    public func writeJson(_ value: some Encodable & Sendable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        write(String(data: data, encoding: .utf8) ?? "{}")
    }

    // MARK: - Process

    public func write(_ result: StartResult) {
        switch result {
        case .success(.started(let pid)): write("Overlay started (PID \(pid))")
        case .failure(.alreadyRunning): writeError("Already running")
        case .failure(.daemonExitedImmediately): writeError("Failed to start (daemon exited immediately)")
        case .failure(.spawnFailed(let detail)): writeError("Failed to start: \(detail)")
        case .failure(.stopFailed): writeError("Failed to restart (could not stop existing process)")
        }
    }

    public func write(_ result: StopResult) {
        switch result {
        case .success(.stopped): write("Stopped")
        case .success(.notRunning): write("Not running")
        case .failure(.lockReleaseTimedOut): writeError("Stopped (warning: lock release timed out)")
        }
    }

    // MARK: - Service

    public func write(_ result: ServiceInstallResult) {
        switch result {
        case .success(.installed(let path)): write("Installed and started: \(path)")
        case .failure(.managedByHomebrew):
            writeError("Already managed by brew services. Run 'brew services stop lyra' first.")
        case .failure(.bootstrapFailed(let status)): writeError("Bootstrap failed (status \(status))")
        case .failure(.failed(let detail)): writeError("Install failed: \(detail)")
        }
    }

    public func write(_ result: ServiceUninstallResult) {
        switch result {
        case .success(.uninstalled): write("Uninstalled")
        case .failure(.managedByHomebrew):
            writeError("Managed by brew services. Run 'brew services stop lyra' instead.")
        case .failure(.notInstalled): writeError("Not installed")
        case .failure(.failed(let detail)): writeError("Uninstall failed: \(detail)")
        }
    }

    // MARK: - Health

    public func write(_ result: HealthCheckReport) {
        let entries: [HealthReportEntry]
        switch result {
        case .success(let passed): entries = passed.entries
        case .failure(let failed): entries = failed.entries
        }

        for entry in entries {
            let tag: String
            switch entry.result.status {
            case .pass: tag = "[PASS]"
            case .fail: tag = "[FAIL]"
            case .skip: tag = "[SKIP]"
            }
            write("\(tag) \(entry.serviceName.padding(toLength: 20, withPad: ".", startingAt: 0)) \(entry.result.detail)")
        }

        write("")
        switch result {
        case .success: write("All checks passed.")
        case .failure(let failed): writeError("\(failed.failedCount) check(s) failed.")
        }
    }

    // MARK: - Config

    public func write(_ result: ConfigWriteResult) {
        switch result {
        case .success(.created(let path)): write("Config file created at \(path)")
        case .failure(.failed(let detail)): writeError("Config error: \(detail)")
        }
    }

    public func write(_ result: ConfigPathResult) {
        switch result {
        case .success(.found(let path)): write(path)
        case .failure(.failed(let detail)): writeError("Config error: \(detail)")
        }
    }

    // MARK: - Benchmark

    public func write(_ update: BenchmarkUpdate) {
        switch update {
        case .header:
            setEcho(enabled: false)
            let header =
                "Scenario".padding(toLength: 16, withPad: " ", startingAt: 0)
                + "Duration".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "CPU(user)".padding(toLength: 11, withPad: " ", startingAt: 0)
                + "CPU(sys)".padding(toLength: 11, withPad: " ", startingAt: 0)
                + "RSS(MB)".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "Peak(MB)"
            write(header)
            write(String(repeating: "─", count: header.count))

        case .live(let entry):
            let row = String(benchmarkRow(entry).prefix(terminalColumns))
            stdoutPrinter("\r\(row)\u{1B}[K", "")
            stdoutFlusher()

        case .completed(let entry):
            setEcho(enabled: true)
            let row = String(benchmarkRow(entry).prefix(terminalColumns))
            stdoutPrinter("\r\(row)\u{1B}[K", "\n")
        }
    }

    private var terminalColumns: Int {
        terminalColumnsProvider()
    }

    private func setEcho(enabled: Bool) {
        echoSetter(enabled)
    }

    private func benchmarkRow(_ entry: BenchmarkEntry) -> String {
        entry.scenario.rawValue.padding(toLength: 16, withPad: " ", startingAt: 0)
            + formatted(seconds: entry.durationSeconds).padding(toLength: 10, withPad: " ", startingAt: 0)
            + formatted(seconds: entry.cpuUserSeconds).padding(toLength: 11, withPad: " ", startingAt: 0)
            + formatted(seconds: entry.cpuSystemSeconds).padding(toLength: 11, withPad: " ", startingAt: 0)
            + formatted(megabytes: entry.currentRSSBytes).padding(toLength: 10, withPad: " ", startingAt: 0)
            + formatted(megabytes: entry.peakRSSBytes)
    }

    private func formatted(seconds: Double) -> String {
        String(format: "%.3fs", seconds)
    }

    private func formatted(megabytes bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}
