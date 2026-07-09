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

    @Test("arguments append title and artist after the configured argv, env vars carry config/cache dirs")
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
