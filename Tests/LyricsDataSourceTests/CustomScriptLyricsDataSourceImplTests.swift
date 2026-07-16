import ConfigDataSource
import Dependencies
import Domain
import Files
import Foundation
import Testing

@testable import LyricsDataSource

@Suite("CustomScriptLyricsDataSourceImpl")
struct CustomScriptLyricsDataSourceImplTests {
    @Test("successful script output returns a LyricsResult with track_name/artist_name/plain_lyrics")
    func successfulOutput() async {
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            processRunner: { _, _, _, _ in
                (status: 0, stdout: #"{"track_name": "Song", "artist_name": "Artist", "plain_lyrics": "La la la"}"#, stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result?.trackName == "Song")
        #expect(result?.artistName == "Artist")
        #expect(result?.plainLyrics == "La la la")
    }

    @Test("non-zero exit code returns nil")
    func nonZeroExitReturnsNil() async {
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            processRunner: { _, _, _, _ in
                (status: 1, stdout: "", stderr: "not found")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("unparseable JSON returns nil")
    func unparseableJSONReturnsNil() async {
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            processRunner: { _, _, _, _ in
                (status: 0, stdout: "not json", stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("missing plain_lyrics returns nil")
    func missingPlainLyricsReturnsNil() async {
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            processRunner: { _, _, _, _ in
                (status: 0, stdout: #"{"track_name": "Song", "artist_name": "Artist"}"#, stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("empty plain_lyrics returns nil")
    func emptyPlainLyricsReturnsNil() async {
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            processRunner: { _, _, _, _ in
                (status: 0, stdout: #"{"track_name": "Song", "artist_name": "Artist", "plain_lyrics": ""}"#, stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("missing track_name returns nil even with non-empty plain_lyrics")
    func missingTrackNameReturnsNil() async {
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            processRunner: { _, _, _, _ in
                (status: 0, stdout: #"{"artist_name": "Artist", "plain_lyrics": "La la la"}"#, stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("empty track_name returns nil even with non-empty plain_lyrics")
    func emptyTrackNameReturnsNil() async {
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            processRunner: { _, _, _, _ in
                (status: 0, stdout: #"{"track_name": "", "artist_name": "Artist", "plain_lyrics": "La la la"}"#, stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("non-absolute executable path returns nil without invoking processRunner")
    func relativeExecutablePathReturnsNil() async {
        let dataSource = makeDataSource(
            fallbackCommand: ["python3", "/path/to/script.py"],
            processRunner: { _, _, _, _ in
                Issue.record("processRunner must not be invoked for a non-absolute executable path")
                return (status: 0, stdout: "", stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("empty fallback_command returns nil without invoking processRunner")
    func emptyFallbackCommandReturnsNilWithoutRunning() async {
        let dataSource = makeDataSource(
            fallbackCommand: [],
            processRunner: { _, _, _, _ in
                Issue.record("processRunner must not be invoked when fallback_command is empty")
                return (status: 0, stdout: "", stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("arguments append title and artist after the configured argv, env vars carry config/cache dirs on top of the parent environment")
    func argumentsAndEnvironment() async {
        let captured = CapturedInvocation()
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py", "--flag"],
            timeoutMs: 1234,
            configDir: "/my/config",
            processRunner: { executable, arguments, environment, timeoutMs in
                await captured.record(executable: executable, arguments: arguments, environment: environment, timeoutMs: timeoutMs)
                return (status: 0, stdout: #"{"plain_lyrics": "x"}"#, stderr: "")
            }
        )
        _ = await dataSource.get(title: "My Title", artist: "My Artist", duration: nil)

        let executable = await captured.executable
        let arguments = await captured.arguments
        let environment = await captured.environment
        let timeoutMs = await captured.timeoutMs
        #expect(executable == "/usr/bin/python3")
        #expect(arguments == ["/path/to/script.py", "--flag", "My Title", "My Artist"])
        #expect(environment?["LYRA_CONFIG_DIR"] == "/my/config")
        #expect(environment?["LYRA_CACHE_DIR"] == CustomScriptLyricsDataSourceImpl.resolvedCacheDir())
        // The lyra-specific keys are merged ON TOP of the full parent environment
        // (not a replacement) — assert a well-known parent var survives alongside them,
        // rather than asserting the dictionary equals exactly the two lyra keys.
        #expect(environment?["PATH"] == ProcessInfo.processInfo.environment["PATH"])
        #expect((environment?.count ?? 0) > 2)
        #expect(timeoutMs == 1234)
    }

    @Test("executeProcess survives pathological timeout values — huge/NaN/infinite clamp instead of trapping")
    func executeProcessClampsPathologicalTimeouts() async throws {
        for pathological in [1e300, .nan, .infinity] as [Double] {
            let result = try await CustomScriptLyricsDataSourceImpl.executeProcess(
                executable: "/bin/echo", arguments: ["ok"], environment: [:], timeoutMs: pathological)
            #expect(result.status == 0)
            #expect(result.stdout == "ok")
        }
        // A negative value clamps to the 1 ms floor — the call must not trap; whether the
        // subprocess beats the 1 ms deadline is timing-dependent, so only no-crash is asserted.
        _ = try await CustomScriptLyricsDataSourceImpl.executeProcess(
            executable: "/bin/echo", arguments: ["ok"], environment: [:], timeoutMs: -5)
    }

    @Test("$LYRA_CONFIG_DIR / ${LYRA_CACHE_DIR} placeholders expand in fallback_command elements")
    func placeholdersExpandInFallbackCommand() async {
        let captured = CapturedInvocation()
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "$LYRA_CONFIG_DIR/scripts/fetch.py", "${LYRA_CACHE_DIR}/state"],
            configDir: "/config/lyra",
            processRunner: { executable, arguments, environment, timeoutMs in
                await captured.record(executable: executable, arguments: arguments, environment: environment, timeoutMs: timeoutMs)
                return (status: 0, stdout: #"{"track_name": "Song", "plain_lyrics": "La"}"#, stderr: "")
            }
        )
        _ = await dataSource.get(title: "Song", artist: "Artist", duration: nil)

        let executable = await captured.executable
        let arguments = await captured.arguments
        let cacheDir = CustomScriptLyricsDataSourceImpl.resolvedCacheDir()
        #expect(executable == "/usr/bin/python3")
        #expect(arguments == ["/config/lyra/scripts/fetch.py", "\(cacheDir)/state", "Song", "Artist"])
    }

    @Test("placeholder-led executable expands before the absolute-path guard and runs")
    func placeholderExecutablePassesAbsolutePathGuard() async {
        let captured = CapturedInvocation()
        let dataSource = makeDataSource(
            fallbackCommand: ["$LYRA_CONFIG_DIR/scripts/fetch.sh"],
            configDir: "/config/lyra",
            processRunner: { executable, arguments, environment, timeoutMs in
                await captured.record(executable: executable, arguments: arguments, environment: environment, timeoutMs: timeoutMs)
                return (status: 0, stdout: #"{"track_name": "Song", "plain_lyrics": "La"}"#, stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result != nil)
        let executable = await captured.executable
        #expect(executable == "/config/lyra/scripts/fetch.sh")
    }

    @Test("search always returns nil — Tier C has no fuzzy-search endpoint")
    func searchReturnsNil() async {
        let dataSource = makeDataSource(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            processRunner: { _, _, _, _ in (status: 0, stdout: "", stderr: "") }
        )
        let result = await dataSource.search(query: "anything")
        #expect(result == nil)
    }

    // MARK: - Real executeProcess (regression guard for the b09c1da waitUntilExit() hang fix)
    //
    // Every test above stubs `processRunner`, so none of them ever runs the real
    // `executeProcess` static function — the exact code whose `waitUntilExit()` was
    // replaced with `terminationHandler` + a 3rd DispatchGroup pair after repeated
    // short-lived invocations were empirically observed to hang (#308 review). These
    // two tests spawn real subprocesses through `executeProcess` directly so a future
    // refactor that reintroduces a blocking wait is caught by the suite.

    @Test("executeProcess spawns a real subprocess repeatedly without hanging")
    func executeProcessRealSubprocessDoesNotHang() async throws {
        let iterations = 50
        let start = ContinuousClock.now

        for i in 0..<iterations {
            let result = try await CustomScriptLyricsDataSourceImpl.executeProcess(
                executable: "/bin/echo",
                arguments: ["hello-\(i)"],
                environment: [:],
                timeoutMs: 3000
            )
            #expect(result.status == 0)
            #expect(result.stdout == "hello-\(i)")
        }

        // 30s budget (vs. a normal-case sub-second run) absorbs CI contention
        // without losing detection power — a genuine hang would still fail
        // this bound many times over.
        let elapsed = start.duration(to: .now)
        #expect(elapsed < .seconds(30))
    }

    @Test("executeProcess returns promptly on timeout instead of waiting out the full sleep duration")
    func executeProcessTimeoutReturnsPromptly() async throws {
        let start = ContinuousClock.now

        let result = try await CustomScriptLyricsDataSourceImpl.executeProcess(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 10"],
            environment: [:],
            timeoutMs: 100
        )

        let elapsed = start.duration(to: .now)
        #expect(result.status == -1)
        #expect(result.stdout.isEmpty)
        #expect(elapsed < .seconds(5))
    }

    @Test("executeProcess throws when the executable cannot be launched")
    func executeProcessThrowsOnLaunchFailure() async {
        await #expect(throws: (any Error).self) {
            try await CustomScriptLyricsDataSourceImpl.executeProcess(
                executable: "/nonexistent/definitely-not-a-real-binary-xyz",
                arguments: [],
                environment: [:],
                timeoutMs: 1000
            )
        }
    }

    @Test("the no-argument init reads fallback_command/timeout from config and runs the resolved script")
    func initReadsConfigAndRunsScript() async throws {
        // A [lyrics] section pointing at /bin/echo (absolute, always present). echo emits
        // non-JSON, so get() returns nil — but constructing via the config-reading init and
        // invoking the real processRunner exercises init(), resolvedCacheDir(), and the
        // processRunner closure that the injectable init bypasses.
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(fallbackCommand: ["/bin/echo", "unused"], timeoutMs: 5000)
        } operation: {
            CustomScriptLyricsDataSourceImpl()
        }

        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("executeProcess force-kills a SIGTERM-ignoring script after the timeout")
    func executeProcessForceKillsStubbornScript() async throws {
        let pidFile = NSTemporaryDirectory() + "lyra-tierc-\(UUID().uuidString).pid"
        defer { try? FileManager.default.removeItem(atPath: pidFile) }

        // The script records its own pid, then ignores SIGTERM and sleeps far past the
        // timeout. Only the SIGTERM→SIGKILL escalation can stop it.
        let result = try await CustomScriptLyricsDataSourceImpl.executeProcess(
            executable: "/bin/sh",
            arguments: ["-c", "echo $$ > '\(pidFile)'; trap '' TERM; sleep 30"],
            environment: [:],
            timeoutMs: 200
        )
        #expect(result.status == -1)

        let pidString =
            (try? String(contentsOfFile: pidFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pid = Int32(pidString) ?? 0
        #expect(pid > 0, "the script should have recorded its pid before ignoring SIGTERM")

        // After the escalation reaps it, kill(pid, 0) fails (ESRCH). Poll rather than
        // sleep a fixed interval — the reap is asynchronous.
        let deadline = ContinuousClock.now + .seconds(3)
        while kill(pid, 0) == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(pid, 0) != 0, "a SIGTERM-ignoring script must be SIGKILLed, not left running")
    }

    // MARK: - Config hot reload (#41)
    //
    // get() must read fallback_command/timeout_ms from configDataSource on EVERY call,
    // never capture them once at init — otherwise an edited [lyrics] section would only
    // take effect after a daemon restart. Proven with a REAL disk-backed ConfigDataSourceImpl
    // (not a stub) so the config file is rewritten between two get() calls on the SAME
    // long-lived DataSource instance.
    @Test("get() re-reads fallback_command/timeout_ms from config on every call, not just at init")
    func reReadsConfigOnEveryCall() async throws {
        let xdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        defer { try? xdgConfig.delete() }
        let lyraDir = try xdgConfig.createSubfolder(named: "lyra")
        let configFile = try lyraDir.createFile(named: "config.toml")
        try configFile.write(
            """
            [lyrics]
            fallback_command = ["/usr/bin/scriptA"]
            timeout_ms = 1000
            """)

        let captured = CapturedInvocation()
        let dataSource = withDependencies {
            $0.configDataSource = ConfigDataSourceImpl(configHome: xdgConfig.path)
        } operation: {
            CustomScriptLyricsDataSourceImpl(processRunner: { executable, arguments, environment, timeoutMs in
                await captured.record(executable: executable, arguments: arguments, environment: environment, timeoutMs: timeoutMs)
                return (status: 0, stdout: #"{"track_name": "T", "plain_lyrics": "L"}"#, stderr: "")
            })
        }

        _ = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(await captured.executable == "/usr/bin/scriptA")
        #expect(await captured.timeoutMs == 1000)

        // Rewrite the config on disk — no new DataSource instance, no restart.
        try configFile.write(
            """
            [lyrics]
            fallback_command = ["/usr/bin/scriptB"]
            timeout_ms = 2000
            """)

        _ = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(await captured.executable == "/usr/bin/scriptB")
        #expect(await captured.timeoutMs == 2000)
    }

    // While a rejected edit (broken required structure) sits on disk, `reload()`
    // keeps the previous style — and the per-call config read here must keep the
    // previous [lyrics] values too, not silently disable the Tier C fallback until
    // the user fixes the file (#337 review).
    @Test("get() keeps the last accepted fallback_command while an invalid config sits on disk")
    func keepsFallbackAcrossRejectedEdit() async throws {
        let xdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        defer { try? xdgConfig.delete() }
        let lyraDir = try xdgConfig.createSubfolder(named: "lyra")
        let configFile = try lyraDir.createFile(named: "config.toml")
        try configFile.write(
            """
            [lyrics]
            fallback_command = ["/usr/bin/scriptA"]
            """)

        let captured = CapturedInvocation()
        let dataSource = withDependencies {
            $0.configDataSource = ConfigDataSourceImpl(configHome: xdgConfig.path)
        } operation: {
            CustomScriptLyricsDataSourceImpl(processRunner: { executable, arguments, environment, timeoutMs in
                await captured.record(executable: executable, arguments: arguments, environment: environment, timeoutMs: timeoutMs)
                return (status: 0, stdout: #"{"track_name": "T", "plain_lyrics": "L"}"#, stderr: "")
            })
        }

        let primed = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(primed != nil)

        // A broken required structure lands on disk: reload() rejects it and keeps
        // the previous config in effect — the fallback must keep running too.
        try configFile.write("wallpaper = [")

        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result != nil)
        #expect(await captured.executable == "/usr/bin/scriptA")
    }
}

/// Builds a `CustomScriptLyricsDataSourceImpl` with `[lyrics]` config values supplied via
/// `StubConfigDataSource` (read fresh by `get()` on every call — see #41). Constructing
/// inside `withDependencies` snapshots the override into the struct's `@Dependency`
/// property for its whole lifetime, so `get()` can be called after this function returns.
private func makeDataSource(
    fallbackCommand: [String],
    timeoutMs: Double = 5000,
    configDir: String = "/config",
    processRunner:
        @escaping @Sendable (String, [String], [String: String], Double) async throws -> (
            status: Int32, stdout: String, stderr: String
        )
) -> CustomScriptLyricsDataSourceImpl {
    withDependencies {
        $0.configDataSource = StubConfigDataSource(fallbackCommand: fallbackCommand, timeoutMs: timeoutMs, configDir: configDir)
    } operation: {
        CustomScriptLyricsDataSourceImpl(processRunner: processRunner)
    }
}

private struct StubConfigDataSource: ConfigDataSource {
    var fallbackCommand: [String] = []
    var timeoutMs: Double = 5000
    var configDir: String = "/config"

    // AppConfig's memberwise init is internal to the Entity module (only its
    // Codable `init(from:)` is public), so a cross-module test builds it via JSON
    // decode instead — same approach as LLMMetadataDataSourceResolveTests.makeConfig().
    func load() -> ConfigLoadResult? {
        let json = """
            {"lyrics": {"fallback_command": \(encodedJSONArray(fallbackCommand)), "timeout_ms": \(timeoutMs)}}
            """
        guard let data = json.data(using: .utf8),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return nil }
        return ConfigLoadResult(config: config, configDir: configDir)
    }
    func tryDecode(strictOptionalSections: Bool) throws -> String { "" }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

private func encodedJSONArray(_ strings: [String]) -> String {
    let data = (try? JSONEncoder().encode(strings)) ?? Data("[]".utf8)
    return String(data: data, encoding: .utf8) ?? "[]"
}

private actor CapturedInvocation {
    private(set) var executable: String?
    private(set) var arguments: [String]?
    private(set) var environment: [String: String]?
    private(set) var timeoutMs: Double?

    func record(executable: String, arguments: [String], environment: [String: String], timeoutMs: Double) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.timeoutMs = timeoutMs
    }
}
