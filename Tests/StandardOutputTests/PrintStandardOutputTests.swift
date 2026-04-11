import Darwin.POSIX
import Domain
import Foundation
import Testing

@testable import StandardOutput

@Suite("PrintStandardOutput", .serialized)
struct PrintStandardOutputTests {
    private let output = PrintStandardOutput()

    @Test("write sends plain messages to stdout")
    func writeMessage() throws {
        let stdout = try captureStdout {
            output.write("hello")
        }
        #expect(stdout == "hello\n")
    }

    @Test("writeError sends errors to stderr")
    func writeError() throws {
        let stderr = try captureStderr {
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

        let stdout = try captureStdout {
            output.writeJson(Payload(z: 2, a: "x"))
        }

        #expect(stdout.contains("\n"))
        #expect(stdout.contains("\"a\" : \"x\""))
        #expect(stdout.contains("\"z\" : 2"))
    }

    @Test("write start results maps each branch to expected output")
    func writeStartResults() throws {
        let started = try captureStdout {
            output.write(.success(.started(pid: 42)))
        }
        let alreadyRunning = try captureStderr {
            output.write(.failure(.alreadyRunning))
        }
        let daemonExited = try captureStderr {
            output.write(.failure(.daemonExitedImmediately))
        }
        let spawnFailed = try captureStderr {
            output.write(.failure(.spawnFailed(detail: "detail")))
        }
        let stopFailed = try captureStderr {
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
        let stopped = try captureStdout {
            output.write(.success(.stopped))
        }
        let notRunning = try captureStdout {
            output.write(.success(.notRunning))
        }
        let timedOut = try captureStderr {
            output.write(.failure(.lockReleaseTimedOut))
        }

        #expect(stopped == "Stopped\n")
        #expect(notRunning == "Not running\n")
        #expect(timedOut == "Stopped (warning: lock release timed out)\n")
    }

    @Test("write service install results maps each branch to expected output")
    func writeServiceInstallResults() throws {
        let installed = try captureStdout {
            output.write(.success(.installed(path: "/tmp/lyra.plist")) as ServiceInstallResult)
        }
        let homebrew = try captureStderr {
            output.write(.failure(.managedByHomebrew) as ServiceInstallResult)
        }
        let bootstrap = try captureStderr {
            output.write(.failure(.bootstrapFailed(status: 5)) as ServiceInstallResult)
        }
        let failed = try captureStderr {
            output.write(.failure(.failed(detail: "write failed")) as ServiceInstallResult)
        }

        #expect(installed == "Installed and started: /tmp/lyra.plist\n")
        #expect(homebrew == "Already managed by brew services. Run 'brew services stop lyra' first.\n")
        #expect(bootstrap == "Bootstrap failed (status 5)\n")
        #expect(failed == "Install failed: write failed\n")
    }

    @Test("write service uninstall results maps each branch to expected output")
    func writeServiceUninstallResults() throws {
        let uninstalled = try captureStdout {
            output.write(.success(.uninstalled) as ServiceUninstallResult)
        }
        let homebrew = try captureStderr {
            output.write(.failure(.managedByHomebrew) as ServiceUninstallResult)
        }
        let notInstalled = try captureStderr {
            output.write(.failure(.notInstalled) as ServiceUninstallResult)
        }
        let failed = try captureStderr {
            output.write(.failure(.failed(detail: "delete failed")) as ServiceUninstallResult)
        }

        #expect(uninstalled == "Uninstalled\n")
        #expect(homebrew == "Managed by brew services. Run 'brew services stop lyra' instead.\n")
        #expect(notInstalled == "Not installed\n")
        #expect(failed == "Uninstall failed: delete failed\n")
    }

    @Test("write health report prints entries and success summary")
    func writeHealthSuccess() throws {
        let stdout = try captureStdout {
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
        let captured = try captureOutput {
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
        let created = try captureStdout {
            output.write(.success(.created(path: "/tmp/config.toml")))
        }
        let configError = try captureStderr {
            output.write(.failure(.failed(detail: "bad config")) as ConfigWriteResult)
        }
        let found = try captureStdout {
            output.write(.success(.found(path: "/tmp/config.toml")))
        }
        let pathError = try captureStderr {
            output.write(.failure(.failed(detail: "missing")) as ConfigPathResult)
        }

        #expect(created == "Config file created at /tmp/config.toml\n")
        #expect(configError == "Config error: bad config\n")
        #expect(found == "/tmp/config.toml\n")
        #expect(pathError == "Config error: missing\n")
    }

    @Test("write benchmark header prints table headings")
    func writeBenchmarkHeader() throws {
        let stdout = try captureStdout {
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

        let live = try captureStdout {
            output.write(.live(entry))
        }
        let completed = try captureStdout {
            output.write(.completed(entry))
        }

        #expect(live.contains("cpu_spike"))
        #expect(live.contains("1.234s"))
        #expect(live.contains("2.5"))
        #expect(live.contains("\u{1B}[K"))
        #expect(completed.contains("cpu_spike"))
        #expect(completed.contains("5.0"))
    }
}

private func captureStdout(_ operation: () throws -> Void) throws -> String {
    try capture(fileDescriptor: STDOUT_FILENO, stream: stdout, operation)
}

private func captureStderr(_ operation: () throws -> Void) throws -> String {
    try capture(fileDescriptor: STDERR_FILENO, stream: stderr, operation)
}

private func captureOutput(_ operation: () throws -> Void) throws -> (stdout: String, stderr: String) {
    let stdoutPipe = try makePipe()
    let stderrPipe = try makePipe()
    var savedStdout = dup(STDOUT_FILENO)
    guard savedStdout >= 0 else {
        _ = close(stdoutPipe.readFD)
        _ = close(stdoutPipe.writeFD)
        _ = close(stderrPipe.readFD)
        _ = close(stderrPipe.writeFD)
        throw currentPOSIXError()
    }
    var savedStderr = dup(STDERR_FILENO)
    guard savedStderr >= 0 else {
        let error = currentPOSIXError()
        _ = close(savedStdout)
        _ = close(stdoutPipe.readFD)
        _ = close(stdoutPipe.writeFD)
        _ = close(stderrPipe.readFD)
        _ = close(stderrPipe.writeFD)
        throw error
    }
    defer {
        if savedStdout >= 0 { _ = close(savedStdout) }
        if savedStderr >= 0 { _ = close(savedStderr) }
    }

    fflush(stdout)
    fflush(stderr)
    guard dup2(stdoutPipe.writeFD, STDOUT_FILENO) >= 0 else {
        _ = close(stdoutPipe.readFD)
        _ = close(stdoutPipe.writeFD)
        _ = close(stderrPipe.readFD)
        _ = close(stderrPipe.writeFD)
        throw currentPOSIXError()
    }
    guard dup2(stderrPipe.writeFD, STDERR_FILENO) >= 0 else {
        let error = currentPOSIXError()
        _ = dup2(savedStdout, STDOUT_FILENO)
        _ = close(stdoutPipe.readFD)
        _ = close(stdoutPipe.writeFD)
        _ = close(stderrPipe.readFD)
        _ = close(stderrPipe.writeFD)
        throw error
    }

    do {
        try operation()
    } catch {
        fflush(stdout)
        fflush(stderr)
        _ = dup2(savedStdout, STDOUT_FILENO)
        _ = dup2(savedStderr, STDERR_FILENO)
        _ = close(stdoutPipe.writeFD)
        _ = close(stderrPipe.writeFD)
        _ = close(stdoutPipe.readFD)
        _ = close(stderrPipe.readFD)
        throw error
    }

    fflush(stdout)
    fflush(stderr)
    _ = dup2(savedStdout, STDOUT_FILENO)
    _ = dup2(savedStderr, STDERR_FILENO)
    _ = close(stdoutPipe.writeFD)
    _ = close(stderrPipe.writeFD)

    let stdoutData = FileHandle(fileDescriptor: stdoutPipe.readFD, closeOnDealloc: true).readDataToEndOfFile()
    let stderrData = FileHandle(fileDescriptor: stderrPipe.readFD, closeOnDealloc: true).readDataToEndOfFile()
    return (
        String(data: stdoutData, encoding: .utf8) ?? "",
        String(data: stderrData, encoding: .utf8) ?? ""
    )
}

private func capture(
    fileDescriptor: Int32,
    stream: UnsafeMutablePointer<FILE>,
    _ operation: () throws -> Void
) throws -> String {
    let (readFD, writeFD) = try makePipe()
    let savedFD = dup(fileDescriptor)
    guard savedFD >= 0 else {
        let error = currentPOSIXError()
        _ = close(readFD)
        _ = close(writeFD)
        throw error
    }
    defer { _ = close(savedFD) }

    fflush(stream)
    guard dup2(writeFD, fileDescriptor) >= 0 else {
        let error = currentPOSIXError()
        _ = close(readFD)
        _ = close(writeFD)
        throw error
    }

    do {
        try operation()
    } catch {
        fflush(stream)
        _ = dup2(savedFD, fileDescriptor)
        _ = close(writeFD)
        _ = close(readFD)
        throw error
    }

    fflush(stream)
    _ = dup2(savedFD, fileDescriptor)
    _ = close(writeFD)

    let data = FileHandle(fileDescriptor: readFD, closeOnDealloc: true).readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

private func makePipe() throws -> (readFD: Int32, writeFD: Int32) {
    let readWrite = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
    defer { readWrite.deallocate() }
    guard pipe(readWrite) == 0 else {
        throw currentPOSIXError()
    }
    return (readWrite[0], readWrite[1])
}

private func currentPOSIXError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
}
