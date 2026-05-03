import Darwin
import Darwin.POSIX
import Domain
import Foundation
import Testing

@testable import StandardOutput

@Suite("PrintStandardOutput", .serialized)
struct PrintStandardOutputTests {
    @Test("write sends plain messages to stdout")
    func writeMessage() throws {
        let stdout = try captureStdout { output in
            output.write("hello")
        }
        #expect(stdout == "hello\n")
    }

    @Test("writeError sends errors to stderr")
    func writeError() throws {
        let stderr = try captureStderr { output in
            output.writeError("boom")
        }
        #expect(stderr == "boom\n")
    }

    @Test("writeJson pretty prints sorted JSON")
    func writeJson() throws {
        struct Payload: Codable, Sendable {
            let z: Int
            let a: String
        }

        let stdout = try captureStdout { output in
            output.writeJson(Payload(z: 2, a: "x"))
        }

        #expect(stdout.contains("\n"))
        #expect(stdout.contains("\"a\" : \"x\""))
        #expect(stdout.contains("\"z\" : 2"))
    }

    @Test("write start results maps each branch to expected output")
    func writeStartResults() throws {
        let started = try captureStdout { output in
            output.write(.success(.started(pid: 42)))
        }
        let alreadyRunning = try captureStderr { output in
            output.write(.failure(.alreadyRunning))
        }
        let daemonExited = try captureStderr { output in
            output.write(.failure(.daemonExitedImmediately))
        }
        let spawnFailed = try captureStderr { output in
            output.write(.failure(.spawnFailed(detail: "detail")))
        }
        let stopFailed = try captureStderr { output in
            output.write(.failure(.stopFailed))
        }

        #expect(started == "Overlay started (PID 42)\n")
        #expect(alreadyRunning == "Already running\n")
        #expect(daemonExited == "Failed to start (daemon exited immediately)\n")
        #expect(spawnFailed.trimmingCharacters(in: .newlines) == "Failed to start: detail")
        #expect(stopFailed == "Failed to restart (could not stop existing process)\n")
    }

    @Test("write stop results maps each branch to expected output")
    func writeStopResults() throws {
        let stopped = try captureStdout { output in
            output.write(.success(.stopped))
        }
        let notRunning = try captureStdout { output in
            output.write(.success(.notRunning))
        }
        let timedOut = try captureStderr { output in
            output.write(.failure(.lockReleaseTimedOut))
        }

        #expect(stopped == "Stopped\n")
        #expect(notRunning == "Not running\n")
        #expect(timedOut == "Stopped (warning: lock release timed out)\n")
    }

    @Test("write service install results maps each branch to expected output")
    func writeServiceInstallResults() throws {
        let installed = try captureStdout { output in
            output.write(.success(.installed(path: "/tmp/lyra.plist")) as ServiceInstallResult)
        }
        let homebrew = try captureStderr { output in
            output.write(.failure(.managedByHomebrew) as ServiceInstallResult)
        }
        let bootstrap = try captureStderr { output in
            output.write(.failure(.bootstrapFailed(status: 5)) as ServiceInstallResult)
        }
        let failed = try captureStderr { output in
            output.write(.failure(.failed(detail: "write failed")) as ServiceInstallResult)
        }

        #expect(installed == "Installed and started: /tmp/lyra.plist\n")
        #expect(homebrew == "Already managed by brew services. Run 'brew services stop lyra' first.\n")
        #expect(bootstrap == "Bootstrap failed (status 5)\n")
        #expect(failed == "Install failed: write failed\n")
    }

    @Test("write service uninstall results maps each branch to expected output")
    func writeServiceUninstallResults() throws {
        let uninstalled = try captureStdout { output in
            output.write(.success(.uninstalled) as ServiceUninstallResult)
        }
        let homebrew = try captureStderr { output in
            output.write(.failure(.managedByHomebrew) as ServiceUninstallResult)
        }
        let notInstalled = try captureStderr { output in
            output.write(.failure(.notInstalled) as ServiceUninstallResult)
        }
        let failed = try captureStderr { output in
            output.write(.failure(.failed(detail: "delete failed")) as ServiceUninstallResult)
        }

        #expect(uninstalled == "Uninstalled\n")
        #expect(homebrew == "Managed by brew services. Run 'brew services stop lyra' instead.\n")
        #expect(notInstalled == "Not installed\n")
        #expect(failed == "Uninstall failed: delete failed\n")
    }

    @Test("write health report prints entries and success summary")
    func writeHealthSuccess() throws {
        let stdout = try captureStdout { output in
            output.write(
                .success(
                    HealthCheckPassed(entries: [
                        HealthReportEntry(
                            serviceName: "Lyrics",
                            result: .init(status: .pass, detail: "ok")
                        ),
                        HealthReportEntry(
                            serviceName: "Metadata",
                            result: .init(status: .skip, detail: "disabled")
                        ),
                    ])
                ))
        }

        #expect(stdout.contains("[PASS] Lyrics"))
        #expect(stdout.contains("[SKIP] Metadata"))
        #expect(stdout.hasSuffix("\nAll checks passed.\n"))
    }

    @Test("write health report prints failures to stderr")
    func writeHealthFailure() throws {
        let captured = try captureOutput { output in
            output.write(
                .failure(
                    HealthCheckFailed(entries: [
                        HealthReportEntry(
                            serviceName: "Lyrics",
                            result: .init(status: .fail, detail: "timeout")
                        ),
                        HealthReportEntry(
                            serviceName: "Metadata",
                            result: .init(status: .pass, detail: "ok")
                        ),
                    ])
                ))
        }

        #expect(captured.stdout.contains("[FAIL] Lyrics"))
        #expect(captured.stdout.contains("[PASS] Metadata"))
        #expect(captured.stderr == "1 check(s) failed.\n")
    }

    @Test("write config results map success and failure output")
    func writeConfigResults() throws {
        let created = try captureStdout { output in
            output.write(.success(.created(path: "/tmp/config.toml")))
        }
        let configError = try captureStderr { output in
            output.write(.failure(.failed(detail: "bad config")) as ConfigWriteResult)
        }
        let found = try captureStdout { output in
            output.write(.success(.found(path: "/tmp/config.toml")))
        }
        let pathError = try captureStderr { output in
            output.write(.failure(.failed(detail: "missing")) as ConfigPathResult)
        }
        let launchSuccess = try captureStdout { output in
            output.write(.success(.launched(path: "/tmp/config.toml")) as ConfigLaunchResult)
        }
        let launchError = try captureStderr { output in
            output.write(.failure(.failed(detail: "launch failed")) as ConfigLaunchResult)
        }

        #expect(created == "Config file created at /tmp/config.toml\n")
        #expect(configError == "Config error: bad config\n")
        #expect(found == "/tmp/config.toml\n")
        #expect(pathError == "Config error: missing\n")
        #expect(launchSuccess.isEmpty)
        #expect(launchError == "Config error: launch failed\n")
    }

    @Test("write benchmark header prints table headings")
    func writeBenchmarkHeader() throws {
        let stdout = try captureStdout { output in
            output.write(.header)
        }

        #expect(stdout.contains("Scenario"))
        #expect(stdout.contains("Duration"))
        #expect(stdout.contains("Peak(MB)"))
    }

    @Test("write benchmark live and completed rows format numbers")
    func writeBenchmarkRows() throws {
        let entry = BenchmarkEntry(
            scenario: .cpuSpike,
            durationSeconds: 1.234,
            cpuUserSeconds: 0.5,
            cpuSystemSeconds: 0.25,
            peakRSSBytes: 5_242_880,
            currentRSSBytes: 2_621_440
        )

        let live = try captureStdout { output in
            output.write(.live(entry))
        }
        let completed = try captureStdout { output in
            output.write(.completed(entry))
        }

        #expect(live.contains("cpu_spike"))
        #expect(live.contains("1.234s"))
        #expect(live.contains("2.5"))
        #expect(live.contains("\u{1B}[K"))
        #expect(completed.contains("cpu_spike"))
        #expect(completed.contains("5.0"))
    }

    @Test("public init benchmark path works with tty streams")
    func publicInitBenchmarkWithTTY() throws {
        let entry = BenchmarkEntry(
            scenario: .cpuSpike,
            durationSeconds: 1.234,
            cpuUserSeconds: 0.5,
            cpuSystemSeconds: 0.25,
            peakRSSBytes: 5_242_880,
            currentRSSBytes: 2_621_440
        )

        _ = try withPseudoTTY(redirectStdin: true, redirectStdout: true) {
            let output = PrintStandardOutput()
            output.write(.header)
            output.write(.live(entry))
            output.write(.completed(entry))
        }
    }

    @Test("public init writeError path does not crash")
    func publicInitWriteErrorSmoke() {
        let output = PrintStandardOutput()
        output.writeError("stderr smoke")
    }
}

private final class OutputRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedStdout = ""
    private var capturedStderr = ""

    var stdout: String { lock.withLock { capturedStdout } }
    var stderr: String { lock.withLock { capturedStderr } }

    func makeOutput(terminalColumns: Int = 80) -> PrintStandardOutput {
        PrintStandardOutput(
            stdoutPrinter: { [weak self] message, terminator in
                self?.appendStdout(message + terminator)
            },
            stderrPrinter: { [weak self] message in
                self?.appendStderr(message)
            },
            stdoutFlusher: {},
            terminalColumnsProvider: { terminalColumns },
            echoSetter: { _ in }
        )
    }

    private func appendStdout(_ chunk: String) {
        lock.withLock {
            capturedStdout += chunk
        }
    }

    private func appendStderr(_ chunk: String) {
        lock.withLock {
            capturedStderr += chunk
        }
    }
}

private func captureStdout(_ operation: (PrintStandardOutput) throws -> Void) throws -> String {
    let recorder = OutputRecorder()
    try operation(recorder.makeOutput())
    return recorder.stdout
}

private func captureStderr(_ operation: (PrintStandardOutput) throws -> Void) throws -> String {
    let recorder = OutputRecorder()
    try operation(recorder.makeOutput())
    return recorder.stderr
}

private func captureOutput(_ operation: (PrintStandardOutput) throws -> Void) throws -> (stdout: String, stderr: String) {
    let recorder = OutputRecorder()
    try operation(recorder.makeOutput())
    return (recorder.stdout, recorder.stderr)
}

private func withPseudoTTY(
    redirectStdin: Bool,
    redirectStdout: Bool,
    columns: UInt16 = 120,
    _ operation: () throws -> Void
) throws -> String {
    var master: Int32 = -1
    var slave: Int32 = -1
    var window = winsize(ws_row: 24, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
    guard openpty(&master, &slave, nil, nil, &window) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    let savedStdin = dup(STDIN_FILENO)
    let savedStdout = dup(STDOUT_FILENO)
    guard savedStdin >= 0, savedStdout >= 0 else {
        _ = close(master)
        _ = close(slave)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    defer {
        _ = dup2(savedStdin, STDIN_FILENO)
        _ = dup2(savedStdout, STDOUT_FILENO)
        _ = close(savedStdin)
        _ = close(savedStdout)
        _ = close(master)
        _ = close(slave)
    }

    if redirectStdin {
        guard dup2(slave, STDIN_FILENO) >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    if redirectStdout {
        guard dup2(slave, STDOUT_FILENO) >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    try operation()
    fflush(stdout)

    _ = dup2(savedStdout, STDOUT_FILENO)
    _ = dup2(savedStdin, STDIN_FILENO)
    _ = close(slave)
    slave = -1

    let data = FileHandle(fileDescriptor: master, closeOnDealloc: false).readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
