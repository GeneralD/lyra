import ArgumentParser
import Dependencies
import Domain
import Testing

@testable import CLI

// MARK: - Shared Test Doubles

private struct StubProcessHandler: ProcessHandler {
    var startResult: StartResult = .success(.started(pid: 42))
    var stopResult: StopResult = .success(.stopped)
    var restartResult: StartResult = .success(.started(pid: 43))

    func start() -> StartResult { startResult }
    func stop() -> StopResult { stopResult }
    func restart() -> StartResult { restartResult }
    func acquireDaemonLock() -> Bool { false }
}

private struct StubServiceHandler: ServiceHandler {
    var installResult: ServiceInstallResult = .success(.installed(path: "/tmp/plist"))
    var uninstallResult: ServiceUninstallResult = .success(.uninstalled)

    func install() -> ServiceInstallResult { installResult }
    func uninstall() -> ServiceUninstallResult { uninstallResult }
}

private struct StubHealthHandler: HealthHandler {
    var report: HealthCheckReport = .success(HealthCheckPassed(entries: []))

    func check() async -> HealthCheckReport { report }
}

private struct StubConfigHandler: ConfigHandler {
    var templateResult: String? = "# config template"
    var writeResult: ConfigWriteResult = .success(.created(path: "/tmp/config.toml"))
    var pathResult: ConfigPathResult = .success(.found(path: "/tmp/config.toml"))

    func template(format: ConfigFormat) -> String? { templateResult }
    func writeTemplate(format: ConfigFormat, force: Bool) -> ConfigWriteResult { writeResult }
    func configPath() -> ConfigPathResult { pathResult }
}

private struct StubTrackHandler: TrackHandler {
    var info = NowPlayingInfo(title: "Test Song", artist: "Test Artist")

    func fetchInfo(query: TrackQuery) async -> NowPlayingInfo { info }
}

private struct StubBenchmarkHandler: BenchmarkHandler {
    var entries: [BenchmarkEntry] = [
        BenchmarkEntry(
            scenario: .idle,
            durationSeconds: 5,
            cpuUserSeconds: 0.01,
            cpuSystemSeconds: 0.005,
            peakRSSBytes: 1024,
            currentRSSBytes: 512
        )
    ]

    func run(scenarios: [BenchmarkScenario], duration: Double) -> AsyncStream<BenchmarkUpdate> {
        let entries = self.entries
        return AsyncStream { continuation in
            continuation.yield(.header)
            for entry in entries {
                continuation.yield(.completed(entry))
            }
            continuation.finish()
        }
    }

    func measure(scenarios: [BenchmarkScenario], duration: Double) async -> [BenchmarkEntry] {
        entries
    }
}

private struct StubVersionHandler: VersionHandler {
    var version: String = "1.0.0"
}

private final class SpyStandardOutput: StandardOutput, @unchecked Sendable {
    private(set) var writtenMessages: [String] = []
    private(set) var writtenJsonCount = 0
    private(set) var writtenBenchmarkUpdates: [BenchmarkUpdate] = []

    func write(_ message: String) { writtenMessages.append(message) }
    func writeError(_ message: String) {}
    func writeJson(_ value: some Encodable & Sendable) { writtenJsonCount += 1 }
    func write(_ result: StartResult) {}
    func write(_ result: StopResult) {}
    func write(_ result: ServiceInstallResult) {}
    func write(_ result: ServiceUninstallResult) {}
    func write(_ result: ConfigWriteResult) {}
    func write(_ result: ConfigPathResult) {}
    func write(_ result: HealthCheckReport) {}
    func write(_ update: BenchmarkUpdate) { writtenBenchmarkUpdates.append(update) }
}

// MARK: - StartCommand

@Suite("StartCommand")
struct StartCommandTests {
    @Test("success path does not throw")
    func successPath() throws {
        try withDependencies {
            $0.processHandler = StubProcessHandler(startResult: .success(.started(pid: 123)))
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = StartCommand()
            try cmd.run()
        }
    }

    @Test("failure path throws ExitCode.failure")
    func failurePath() {
        withDependencies {
            $0.processHandler = StubProcessHandler(startResult: .failure(.alreadyRunning))
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = StartCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }

    @Test("spawn failure throws ExitCode.failure")
    func spawnFailure() {
        withDependencies {
            $0.processHandler = StubProcessHandler(
                startResult: .failure(.spawnFailed(detail: "exec failed"))
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = StartCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }
}

// MARK: - StopCommand

@Suite("StopCommand")
struct StopCommandTests {
    @Test("stopped successfully does not throw")
    func stopped() throws {
        try withDependencies {
            $0.processHandler = StubProcessHandler(stopResult: .success(.stopped))
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = StopCommand()
            try cmd.run()
        }
    }

    @Test("not running does not throw")
    func notRunning() throws {
        try withDependencies {
            $0.processHandler = StubProcessHandler(stopResult: .success(.notRunning))
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = StopCommand()
            try cmd.run()
        }
    }

    @Test("lock release timed out throws ExitCode.failure")
    func lockReleaseTimedOut() {
        withDependencies {
            $0.processHandler = StubProcessHandler(stopResult: .failure(.lockReleaseTimedOut))
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = StopCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }
}

// MARK: - RestartCommand

@Suite("RestartCommand")
struct RestartCommandTests {
    @Test("success path does not throw")
    func successPath() throws {
        try withDependencies {
            $0.processHandler = StubProcessHandler(restartResult: .success(.started(pid: 99)))
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = RestartCommand()
            try cmd.run()
        }
    }

    @Test("failure path throws ExitCode.failure")
    func failurePath() {
        withDependencies {
            $0.processHandler = StubProcessHandler(restartResult: .failure(.stopFailed))
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = RestartCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }
}

// MARK: - HealthcheckCommand

@Suite("HealthcheckCommand")
struct HealthcheckCommandTests {
    @Test("all checks pass does not throw")
    func allPass() async throws {
        try await withDependencies {
            $0.healthHandler = StubHealthHandler(
                report: .success(
                    HealthCheckPassed(entries: [
                        HealthReportEntry(
                            serviceName: "A",
                            result: HealthCheckResult(status: .pass, detail: "ok")
                        )
                    ]))
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = HealthcheckCommand()
            try await cmd.run()
        }
    }

    @Test("some checks fail throws ExitCode.failure")
    func someFail() async {
        await withDependencies {
            $0.healthHandler = StubHealthHandler(
                report: .failure(
                    HealthCheckFailed(entries: [
                        HealthReportEntry(
                            serviceName: "A",
                            result: HealthCheckResult(status: .fail, detail: "unreachable")
                        )
                    ]))
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = HealthcheckCommand()
            await #expect(throws: ExitCode.failure) {
                try await cmd.run()
            }
        }
    }
}

// MARK: - ServiceInstallCommand

@Suite("ServiceInstallCommand")
struct ServiceInstallCommandTests {
    @Test("stop succeeds and install succeeds does not throw")
    func bothSucceed() throws {
        try withDependencies {
            $0.processHandler = StubProcessHandler(stopResult: .success(.stopped))
            $0.serviceHandler = StubServiceHandler(
                installResult: .success(.installed(path: "/tmp/plist"))
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = ServiceInstallCommand()
            try cmd.run()
        }
    }

    @Test("stop fails throws before install")
    func stopFails() {
        withDependencies {
            $0.processHandler = StubProcessHandler(stopResult: .failure(.lockReleaseTimedOut))
            $0.serviceHandler = StubServiceHandler()
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = ServiceInstallCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }

    @Test("stop succeeds but install fails throws ExitCode.failure")
    func installFails() {
        withDependencies {
            $0.processHandler = StubProcessHandler(stopResult: .success(.stopped))
            $0.serviceHandler = StubServiceHandler(
                installResult: .failure(.managedByHomebrew)
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = ServiceInstallCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }
}

// MARK: - ServiceUninstallCommand

@Suite("ServiceUninstallCommand")
struct ServiceUninstallCommandTests {
    @Test("uninstall succeeds and stop succeeds does not throw")
    func bothSucceed() throws {
        try withDependencies {
            $0.serviceHandler = StubServiceHandler(
                uninstallResult: .success(.uninstalled)
            )
            $0.processHandler = StubProcessHandler(stopResult: .success(.stopped))
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = ServiceUninstallCommand()
            try cmd.run()
        }
    }

    @Test("uninstall fails throws ExitCode.failure")
    func uninstallFails() {
        withDependencies {
            $0.serviceHandler = StubServiceHandler(
                uninstallResult: .failure(.notInstalled)
            )
            $0.processHandler = StubProcessHandler()
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = ServiceUninstallCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }

    @Test("uninstall succeeds but stop fails throws ExitCode.failure")
    func stopFails() {
        withDependencies {
            $0.serviceHandler = StubServiceHandler(
                uninstallResult: .success(.uninstalled)
            )
            $0.processHandler = StubProcessHandler(stopResult: .failure(.lockReleaseTimedOut))
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = ServiceUninstallCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }
}

// MARK: - ConfigTemplateCommand

@Suite("ConfigTemplateCommand")
struct ConfigTemplateCommandTests {
    @Test("template returns string does not throw")
    func templateExists() throws {
        try withDependencies {
            $0.configHandler = StubConfigHandler(templateResult: "# toml template")
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = try ConfigTemplateCommand.parse([])
            try cmd.run()
        }
    }

    @Test("template returns nil throws ValidationError")
    func templateNil() throws {
        try withDependencies {
            $0.configHandler = StubConfigHandler(templateResult: nil)
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = try ConfigTemplateCommand.parse([])
            #expect(throws: ValidationError.self) {
                try cmd.run()
            }
        }
    }
}

// MARK: - ConfigInitCommand

@Suite("ConfigInitCommand")
struct ConfigInitCommandTests {
    @Test("success path does not throw")
    func successPath() throws {
        try withDependencies {
            $0.configHandler = StubConfigHandler(
                writeResult: .success(.created(path: "/tmp/config.toml"))
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = try ConfigInitCommand.parse([])
            try cmd.run()
        }
    }

    @Test("failure path throws ExitCode.failure")
    func failurePath() throws {
        try withDependencies {
            $0.configHandler = StubConfigHandler(
                writeResult: .failure(.failed(detail: "file exists"))
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = try ConfigInitCommand.parse([])
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }
}

// MARK: - ConfigEditCommand

@Suite("ConfigEditCommand")
struct ConfigEditCommandTests {
    @Test("failure path when config not found throws ExitCode.failure")
    func configNotFound() {
        withDependencies {
            $0.configHandler = StubConfigHandler(
                pathResult: .failure(.failed(detail: "not found"))
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = ConfigEditCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }
}

// MARK: - ConfigOpenCommand

@Suite("ConfigOpenCommand")
struct ConfigOpenCommandTests {
    @Test("failure path when config not found throws ExitCode.failure")
    func configNotFound() {
        withDependencies {
            $0.configHandler = StubConfigHandler(
                pathResult: .failure(.failed(detail: "not found"))
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = ConfigOpenCommand()
            #expect(throws: ExitCode.failure) {
                try cmd.run()
            }
        }
    }
}

// MARK: - TrackCommand

@Suite("TrackCommand")
struct TrackCommandTests {
    @Test("fetches info and writes JSON without throwing")
    func fetchInfo() async throws {
        try await withDependencies {
            $0.trackHandler = StubTrackHandler(
                info: NowPlayingInfo(title: "Song", artist: "Artist")
            )
            $0.standardOutput = SpyStandardOutput()
        } operation: {
            var cmd = try TrackCommand.parse([])
            try await cmd.run()
        }
    }
}

// MARK: - BenchmarkCommand

@Suite("BenchmarkCommand")
struct BenchmarkCommandTests {
    @Test("parse rejects zero duration via validate")
    func zeroDurationRejected() {
        #expect(throws: (any Error).self) {
            try BenchmarkCommand.parse(["--duration", "0"])
        }
    }

    @Test("parse accepts positive duration")
    func positiveDurationAccepted() throws {
        _ = try BenchmarkCommand.parse(["--duration", "5"])
    }

    @Test("json mode calls measure and writeJson")
    func jsonMode() async throws {
        let spy = SpyStandardOutput()
        try await withDependencies {
            $0.benchmarkHandler = StubBenchmarkHandler()
            $0.standardOutput = spy
        } operation: {
            var cmd = try BenchmarkCommand.parse(["--json"])
            try await cmd.run()
        }
        #expect(spy.writtenJsonCount == 1)
    }

    @Test("stream mode iterates run and calls write for each update")
    func streamMode() async throws {
        let spy = SpyStandardOutput()
        try await withDependencies {
            $0.benchmarkHandler = StubBenchmarkHandler()
            $0.standardOutput = spy
        } operation: {
            var cmd = try BenchmarkCommand.parse([])
            try await cmd.run()
        }
        #expect(spy.writtenBenchmarkUpdates.contains { if case .header = $0 { true } else { false } })
        #expect(spy.writtenBenchmarkUpdates.contains { if case .completed = $0 { true } else { false } })
    }
}

// MARK: - VersionCommand

@Suite("VersionCommand unit")
struct VersionCommandUnitTests {
    @Test("writes version string")
    func writesVersion() {
        let spy = SpyStandardOutput()
        withDependencies {
            $0.versionHandler = StubVersionHandler(version: "2.0.0")
            $0.standardOutput = spy
        } operation: {
            let cmd = VersionCommand()
            cmd.run()
        }
        #expect(spy.writtenMessages.contains("2.0.0"))
    }
}
