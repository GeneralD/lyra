import Dependencies
import Domain
import Foundation

public struct CustomScriptLyricsDataSourceImpl: Sendable {
    // Config values (fallback_command, timeout_ms, configDir) are deliberately NOT
    // captured here at init — `configDataSource` is read fresh inside `get()` on every
    // call, mirroring LLMMetadataDataSourceImpl, so an edited [lyrics] section takes
    // effect on the daemon's very next lookup without a restart (#41).
    @Dependency(\.configDataSource) private var configDataSource
    let processRunner:
        @Sendable (String, [String], [String: String], Double) async throws -> (
            status: Int32, stdout: String, stderr: String
        )

    public init() {
        // Resolve the executor from the context active at init (as the daemon's live DI
        // graph provides it) and capture it — a construction-time `withDependencies`
        // override then sticks, mirroring how `configDataSource` is captured.
        @Dependency(\.processExecutor) var processExecutor
        self.init(processRunner: { executable, arguments, environment, timeoutMs in
            try await processExecutor.run(
                executable: executable, arguments: arguments, environment: environment, timeoutMs: timeoutMs)
        })
    }

    // Test seam: inject a processRunner spy/stub. Config values are supplied via
    // `@Dependency(\.configDataSource)` — tests override it with `withDependencies`.
    init(
        processRunner:
            @escaping @Sendable (String, [String], [String: String], Double) async throws -> (
                status: Int32, stdout: String, stderr: String
            )
    ) {
        self.processRunner = processRunner
    }

    static func resolvedCacheDir() -> String {
        let base =
            ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(NSHomeDirectory())/.cache"
        return "\(base)/lyra"
    }
}

extension CustomScriptLyricsDataSourceImpl: LyricsDataSource {
    public func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        // Read config fresh on every call (never captured at init) so an edited
        // fallback_command/timeout_ms takes effect on the daemon's next lookup (#41).
        let loaded = configDataSource.load()
        let lyrics = loaded?.config.lyrics
        let fallbackCommand = lyrics?.fallbackCommand ?? []
        let timeoutMs = lyrics?.timeoutMs.value ?? 5000
        // The configDir must come from the same load result: while a broken edit
        // sits on disk, load() serves the last-good config, whose configDir can
        // differ from the current on-disk candidate's parent — mixing the two
        // would expand $LYRA_CONFIG_DIR against a directory the served config
        // never lived in.
        let configDir = loaded?.configDir ?? configDataSource.configDir
        let cacheDir = Self.resolvedCacheDir()

        // Placeholders expand BEFORE the absolute-path guard so a config can lead with
        // "$LYRA_CONFIG_DIR/..." and still satisfy the absolute-executable contract.
        let command = fallbackCommand.map { Self.expandedPlaceholders($0, configDir: configDir, cacheDir: cacheDir) }
        // The executable must be an absolute path — a launchd-run daemon has a minimal
        // PATH, so relative paths (resolved against the daemon's CWD) would behave
        // unpredictably and diverge from the documented contract. Reject them up front.
        guard let executable = command.first, executable.hasPrefix("/") else { return nil }
        let arguments = Array(command.dropFirst()) + [title, artist]
        // Merge onto the parent environment rather than replacing it — Process.environment
        // REPLACES the child's entire environment when set, and the user's custom script
        // still needs PATH/HOME/LANG/etc. to run like a normal subprocess (#308 review).
        let environment = ProcessInfo.processInfo.environment.merging(
            ["LYRA_CONFIG_DIR": configDir, "LYRA_CACHE_DIR": cacheDir]
        ) { _, new in new }

        // Require a non-empty track_name: LyricsMatchValidator skips the title-similarity
        // check when the result title is nil/empty, so a script that emits only
        // plain_lyrics (or a generic response) would otherwise slip past validation and
        // reintroduce the unvalidated-cache path Tier C exists to prevent.
        guard let (status, stdout, _) = try? await processRunner(executable, arguments, environment, timeoutMs),
            status == 0,
            let data = stdout.data(using: .utf8),
            let output = try? JSONDecoder().decode(ScriptOutput.self, from: data),
            let trackName = output.trackName, !trackName.isEmpty,
            let plainLyrics = output.plainLyrics, !plainLyrics.isEmpty
        else { return nil }

        return LyricsResult(trackName: trackName, artistName: output.artistName, plainLyrics: plainLyrics)
    }

    public func search(query: String) async -> [LyricsResult]? { nil }

    /// Expands `$LYRA_CONFIG_DIR` / `$LYRA_CACHE_DIR` (and their `${…}` forms) in a
    /// fallback_command element, so configs can locate scripts relative to lyra's own
    /// directories instead of hardcoding machine-specific absolute paths.
    private static func expandedPlaceholders(_ element: String, configDir: String, cacheDir: String) -> String {
        [
            ("${LYRA_CONFIG_DIR}", configDir), ("$LYRA_CONFIG_DIR", configDir),
            ("${LYRA_CACHE_DIR}", cacheDir), ("$LYRA_CACHE_DIR", cacheDir),
        ].reduce(element) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

private struct ScriptOutput: Decodable {
    let trackName: String?
    let artistName: String?
    let plainLyrics: String?

    enum CodingKeys: String, CodingKey {
        case trackName = "track_name"
        case artistName = "artist_name"
        case plainLyrics = "plain_lyrics"
    }
}

// The subprocess plumbing that used to live here (an `executeProcess` static with a
// real clock, blocking pipe drain, and SIGTERM→SIGKILL timeout) moved to
// `ProcessExecutor` + `DarwinGateway.runProcess` (#340) so the timeout oracle is
// abstracted and testable. The no-arg init's live `processRunner` now delegates to
// `@Dependency(\.processExecutor)`.
