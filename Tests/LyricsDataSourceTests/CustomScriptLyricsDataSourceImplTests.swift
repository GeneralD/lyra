import Domain
import Foundation
import Testing

@testable import LyricsDataSource

@Suite("CustomScriptLyricsDataSourceImpl")
struct CustomScriptLyricsDataSourceImplTests {
    @Test("successful script output returns a LyricsResult with track_name/artist_name/plain_lyrics")
    func successfulOutput() async {
        let dataSource = CustomScriptLyricsDataSourceImpl(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            timeoutMs: 5000,
            configDir: "/config",
            cacheDir: "/cache",
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
        let dataSource = CustomScriptLyricsDataSourceImpl(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            timeoutMs: 5000,
            configDir: "/config",
            cacheDir: "/cache",
            processRunner: { _, _, _, _ in
                (status: 1, stdout: "", stderr: "not found")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("unparseable JSON returns nil")
    func unparseableJSONReturnsNil() async {
        let dataSource = CustomScriptLyricsDataSourceImpl(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            timeoutMs: 5000,
            configDir: "/config",
            cacheDir: "/cache",
            processRunner: { _, _, _, _ in
                (status: 0, stdout: "not json", stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("missing plain_lyrics returns nil")
    func missingPlainLyricsReturnsNil() async {
        let dataSource = CustomScriptLyricsDataSourceImpl(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            timeoutMs: 5000,
            configDir: "/config",
            cacheDir: "/cache",
            processRunner: { _, _, _, _ in
                (status: 0, stdout: #"{"track_name": "Song", "artist_name": "Artist"}"#, stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("empty plain_lyrics returns nil")
    func emptyPlainLyricsReturnsNil() async {
        let dataSource = CustomScriptLyricsDataSourceImpl(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            timeoutMs: 5000,
            configDir: "/config",
            cacheDir: "/cache",
            processRunner: { _, _, _, _ in
                (status: 0, stdout: #"{"track_name": "Song", "artist_name": "Artist", "plain_lyrics": ""}"#, stderr: "")
            }
        )
        let result = await dataSource.get(title: "Song", artist: "Artist", duration: nil)
        #expect(result == nil)
    }

    @Test("empty fallback_command returns nil without invoking processRunner")
    func emptyFallbackCommandReturnsNilWithoutRunning() async {
        let dataSource = CustomScriptLyricsDataSourceImpl(
            fallbackCommand: [],
            timeoutMs: 5000,
            configDir: "/config",
            cacheDir: "/cache",
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
        let dataSource = CustomScriptLyricsDataSourceImpl(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py", "--flag"],
            timeoutMs: 1234,
            configDir: "/my/config",
            cacheDir: "/my/cache",
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
        #expect(environment?["LYRA_CACHE_DIR"] == "/my/cache")
        // The lyra-specific keys are merged ON TOP of the full parent environment
        // (not a replacement) — assert a well-known parent var survives alongside them,
        // rather than asserting the dictionary equals exactly the two lyra keys.
        #expect(environment?["PATH"] == ProcessInfo.processInfo.environment["PATH"])
        #expect((environment?.count ?? 0) > 2)
        #expect(timeoutMs == 1234)
    }

    @Test("search always returns nil — Tier C has no fuzzy-search endpoint")
    func searchReturnsNil() async {
        let dataSource = CustomScriptLyricsDataSourceImpl(
            fallbackCommand: ["/usr/bin/python3", "/path/to/script.py"],
            timeoutMs: 5000,
            configDir: "/config",
            cacheDir: "/cache",
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
