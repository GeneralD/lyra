# 確信度ベースのメタデータ+歌詞解決サイクル Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two existing bugs (LLM-cache short-circuit in `MetadataRepositoryImpl`, wrong cache key in `LyricsRepositoryImpl`) and add a validated Tier A→B→C lyrics-matching cycle — where Tier C is a user-pluggable custom script — so lyra only ever caches a metadata+lyrics pair it has actually confirmed, falling back to raw (unprocessed) title/artist display when nothing validates.

**Architecture:** All changes are localized to existing files/modules — no new SPM target, no new cross-UseCase coordinator. `MetadataRepositoryImpl` stops short-circuiting across LLM/MusicBrainz/Regex and appends the raw track as a final candidate. `LyricsRepositoryImpl` gains Tier A (existing `.get()`, now keyed correctly)/Tier B (existing `.search()` + new title-similarity/duration validation)/Tier C (new user-script `LyricsDataSource`) tiers, each looping across all candidates and caching under the actually-matched candidate's key. `TrackInteractorImpl` gets a 2-line display-fallback fix so an unvalidated candidate guess never leaks into the final display when lyrics aren't found.

**Tech Stack:** Swift 6, swift-dependencies (`@Dependency`), Swift Testing (`@Test`/`#expect`), Foundation `Process`/`Pipe` for subprocess execution.

**Spec:** `docs/superpowers/specs/2026-07-09-confidence-based-lyrics-resolution-design.md` (approved, PR #309).

---

## File Structure

**Create:**

- `Sources/Entity/Config/LyricsConfig.swift` — new Entity, mirrors `AIConfig`
- `Sources/LyricsRepository/LyricsMatchValidator.swift` — pure struct, title similarity + duration tolerance
- `Sources/LyricsDataSource/CustomScriptLyricsDataSourceImpl.swift` — Tier C `LyricsDataSource` conformance, argv-array subprocess spawn with timeout
- `Tests/EntityTests/LyricsConfigTests.swift` — none needed (Entity is pure data per `swift-conventions.md`; covered instead by the `ConfigDecodingTests.swift` addition in Task 1)
- `Tests/LyricsRepositoryTests/LyricsMatchValidatorTests.swift` — validator unit tests
- `Tests/LyricsDataSourceTests/CustomScriptLyricsDataSourceImplTests.swift` — Tier C data source tests
- `Tests/TrackInteractorTests/TrackInteractorFallbackDisplayTests.swift` — display-fallback regression test

**Modify:**

- `Sources/Entity/Config/AppConfig.swift` — add `lyrics: LyricsConfig?` field
- `Sources/Domain/DataSource/ConfigDataSource.swift` — add `configDir: String { get }`
- `Sources/ConfigDataSource/ConfigDataSourceImpl.swift` — implement `configDir`
- `Sources/MetadataRepository/MetadataRepositoryImpl.swift` — fix bug 1 (no short-circuit, append raw)
- `Sources/Domain/DataSource/LyricsDataSource.swift` — add `customScriptLyricsDataSource` DI key
- `Sources/DependencyInjection/DataSourceRegistration.swift` — register `CustomScriptLyricsDataSourceImpl`
- `Sources/LyricsRepository/LyricsRepositoryImpl.swift` — fix bug 2, add Tier B validation, wire Tier C
- `Sources/TrackInteractor/TrackInteractorImpl.swift` — fix display fallback (line ~209-210)
- `Tests/ConfigDataSourceTests/ConfigDecodingTests.swift` — add `[lyrics]` decode tests
- `Tests/ConfigDataSourceTests/` — add `configDir` resolution test (new suite in a new or existing file, see Task 2)
- `Tests/MetadataRepositoryTests/MetadataRepositoryTests.swift` — rewrite tests asserting the old short-circuit
- `Tests/LyricsRepositoryTests/LyricsRepositoryTests.swift` — add cache-key-attribution tests
- `README.md` — Tier C config docs + utamap.com sample script
- `CLAUDE.md` — Key Design Decisions entry, Build & Test (no new commands), module table (no new module)
- `AGENTS.md` — mirror the CLAUDE.md decision summary

No new `.target`/`.testTarget` entries in `Package.swift` — every new file lands in an existing module (`Entity`, `LyricsRepository`, `LyricsDataSource`, `Domain`, `ConfigDataSource`, `MetadataRepository`, `TrackInteractor`, `DependencyInjection`) or an existing test target.

---

### Task 1: `LyricsConfig` Entity + `AppConfig.lyrics` field

**Files:**

- Create: `Sources/Entity/Config/LyricsConfig.swift`
- Modify: `Sources/Entity/Config/AppConfig.swift`
- Test: `Tests/ConfigDataSourceTests/ConfigDecodingTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/ConfigDataSourceTests/ConfigDecodingTests.swift`, inside `DefaultValueTests`:

```swift
    @Test("missing [lyrics] section produces nil")
    func noLyricsSection() throws {
        let config = try decode("")
        #expect(config.lyrics == nil)
    }
```

Add a new suite at the end of the file (before the closing of the file, as a top-level `@Suite`):

```swift
// MARK: - Lyrics config (TOML)

@Suite("Lyrics TOML decoding")
struct LyricsTomlDecodingTests {
    @Test("fallback_command and timeout_ms both specified")
    func fullySpecified() throws {
        let config = try decode(
            """
            [lyrics]
            fallback_command = ["/usr/bin/python3", "/path/to/script.py"]
            timeout_ms = 8000
            """)
        #expect(config.lyrics?.fallbackCommand == ["/usr/bin/python3", "/path/to/script.py"])
        #expect(config.lyrics?.timeoutMs.value == 8000)
    }

    @Test("timeout_ms omitted defaults to 5000")
    func timeoutDefaultsTo5000() throws {
        let config = try decode(
            """
            [lyrics]
            fallback_command = ["/usr/bin/python3", "/path/to/script.py"]
            """)
        #expect(config.lyrics?.fallbackCommand == ["/usr/bin/python3", "/path/to/script.py"])
        #expect(config.lyrics?.timeoutMs.value == 5000)
    }

    @Test("fallback_command omitted defaults to empty array")
    func fallbackCommandDefaultsToEmpty() throws {
        let config = try decode(
            """
            [lyrics]
            timeout_ms = 3000
            """)
        #expect(config.lyrics?.fallbackCommand == [])
        #expect(config.lyrics?.timeoutMs.value == 3000)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigDecodingTests`
Expected: FAIL — `config.lyrics` does not exist on `AppConfig` (compile error).

- [ ] **Step 3: Create `LyricsConfig` Entity**

Write `Sources/Entity/Config/LyricsConfig.swift`:

```swift
public struct LyricsConfig {
    public let fallbackCommand: [String]
    public let timeoutMs: FlexibleDouble

    public init(fallbackCommand: [String] = [], timeoutMs: FlexibleDouble = 5000) {
        self.fallbackCommand = fallbackCommand
        self.timeoutMs = timeoutMs
    }
}

extension LyricsConfig: Sendable {}
extension LyricsConfig: Equatable {}

extension LyricsConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case fallbackCommand = "fallback_command"
        case timeoutMs = "timeout_ms"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fallbackCommand = try c.decodeIfPresent([String].self, forKey: .fallbackCommand) ?? []
        timeoutMs = try c.decodeIfPresent(FlexibleDouble.self, forKey: .timeoutMs) ?? 5000
    }
}
```

- [ ] **Step 4: Add `lyrics` field to `AppConfig`**

Edit `Sources/Entity/Config/AppConfig.swift` — add the stored property, default, `CodingKeys` case, and decode line:

```swift
public struct AppConfig {
    public let text: TextConfig
    public let artwork: ArtworkConfig
    public let ripple: RippleConfig
    public let spectrum: SpectrumConfig
    public let screen: ScreenSelector
    public let screenDebounce: FlexibleDouble
    public let wallpaper: WallpaperConfig?
    public let ai: AIConfig?
    public let lyrics: LyricsConfig?
}

extension AppConfig: Sendable {}

extension AppConfig {
    public static let defaults = AppConfig(
        text: .defaults, artwork: .defaults, ripple: .defaults, spectrum: .defaults, screen: .main, screenDebounce: 5,
        wallpaper: nil, ai: nil, lyrics: nil)
}

extension AppConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case text, artwork, ripple, spectrum, screen
        case screenDebounce = "screen_debounce"
        case wallpaper, ai, lyrics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(TextConfig.self, forKey: .text) ?? Self.defaults.text
        artwork = try c.decodeIfPresent(ArtworkConfig.self, forKey: .artwork) ?? Self.defaults.artwork
        ripple = try c.decodeIfPresent(RippleConfig.self, forKey: .ripple) ?? Self.defaults.ripple
        spectrum = try c.decodeIfPresent(SpectrumConfig.self, forKey: .spectrum) ?? Self.defaults.spectrum
        screen = try c.decodeIfPresent(ScreenSelector.self, forKey: .screen) ?? Self.defaults.screen
        screenDebounce = try c.decodeIfPresent(FlexibleDouble.self, forKey: .screenDebounce) ?? Self.defaults.screenDebounce
        wallpaper = try c.decodeIfPresent(WallpaperConfig.self, forKey: .wallpaper) ?? Self.defaults.wallpaper
        ai = try? c.decodeIfPresent(AIConfig.self, forKey: .ai) ?? Self.defaults.ai
        lyrics = try? c.decodeIfPresent(LyricsConfig.self, forKey: .lyrics) ?? Self.defaults.lyrics
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ConfigDecodingTests`
Expected: PASS (all `DefaultValueTests` and `LyricsTomlDecodingTests` cases green).

- [ ] **Step 6: Commit**

```bash
git add Sources/Entity/Config/LyricsConfig.swift Sources/Entity/Config/AppConfig.swift Tests/ConfigDataSourceTests/ConfigDecodingTests.swift
git commit -m "feat(#308): LyricsConfig Entity + AppConfig.lyrics field"
```

---

### Task 2: `ConfigDataSource.configDir` property

**Files:**

- Modify: `Sources/Domain/DataSource/ConfigDataSource.swift`
- Modify: `Sources/ConfigDataSource/ConfigDataSourceImpl.swift`
- Test: `Tests/ConfigDataSourceTests/ConfigDataSourceImplTests.swift` (new file — no existing suite covers `ConfigDataSourceImpl` directly by name; the existing `ConfigDecodingTests.swift`/`ConfigTemplateTests.swift` test decoding/templating only)

- [ ] **Step 1: Write the failing test**

Create `Tests/ConfigDataSourceTests/ConfigDataSourceImplTests.swift`:

```swift
import Foundation
import Testing

@testable import ConfigDataSource

@Suite("ConfigDataSourceImpl.configDir")
struct ConfigDataSourceImplConfigDirTests {
    @Test("configDir falls back to home directory when no config file exists")
    func fallsBackToHomeWhenNoConfigFile() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-configdir-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let emptyXdgConfig = tempHome.appendingPathComponent("empty-xdg-config")
        try FileManager.default.createDirectory(at: emptyXdgConfig, withIntermediateDirectories: true)

        let dataSource = ConfigDataSourceImpl(configHome: emptyXdgConfig.path)
        // No lyra/config.{toml,json} under emptyXdgConfig, and no ~/.lyra fallback exists
        // in this isolated temp dir, so findConfigFile() returns nil and configDir must
        // still resolve to *some* absolute path rather than crash or return empty.
        #expect(!dataSource.configDir.isEmpty)
    }

    @Test("configDir matches the discovered config file's parent directory")
    func matchesDiscoveredConfigFileParent() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-configdir-test-\(UUID().uuidString)")
        let xdgConfig = tempHome.appendingPathComponent("xdg-config")
        let lyraDir = xdgConfig.appendingPathComponent("lyra")
        try FileManager.default.createDirectory(at: lyraDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let configFile = lyraDir.appendingPathComponent("config.toml")
        try "".write(to: configFile, atomically: true, encoding: .utf8)

        let dataSource = ConfigDataSourceImpl(configHome: xdgConfig.path)
        #expect(dataSource.configDir == lyraDir.path)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigDataSourceImplConfigDirTests`
Expected: FAIL — `configDir` is not a member of `ConfigDataSourceImpl` (compile error).

- [ ] **Step 3: Add `configDir` to the protocol**

Edit `Sources/Domain/DataSource/ConfigDataSource.swift`:

```swift
import Dependencies

public protocol ConfigDataSource: Sendable {
    func load() -> ConfigLoadResult?
    func tryDecode() throws -> String
    func template(format: ConfigFormat) -> String?
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String
    var existingConfigPath: String? { get }
    var configDir: String { get }
}

public enum ConfigDataSourceKey: TestDependencyKey {
    public static let testValue: any ConfigDataSource = UnimplementedConfigDataSource()
}

extension DependencyValues {
    public var configDataSource: any ConfigDataSource {
        get { self[ConfigDataSourceKey.self] }
        set { self[ConfigDataSourceKey.self] = newValue }
    }
}

private struct UnimplementedConfigDataSource: ConfigDataSource {
    func load() -> ConfigLoadResult? { nil }
    func tryDecode() throws -> String { "" }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
    var configDir: String { "" }
}
```

- [ ] **Step 4: Implement `configDir` in `ConfigDataSourceImpl`**

Edit `Sources/ConfigDataSource/ConfigDataSourceImpl.swift` — add the computed property next to `existingConfigPath`:

```swift
    public var existingConfigPath: String? {
        findConfigFile()?.path
    }

    public var configDir: String {
        findConfigFile()?.parent?.path ?? Folder.home.path
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ConfigDataSourceImplConfigDirTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Domain/DataSource/ConfigDataSource.swift Sources/ConfigDataSource/ConfigDataSourceImpl.swift Tests/ConfigDataSourceTests/ConfigDataSourceImplTests.swift
git commit -m "feat(#308): expose ConfigDataSource.configDir for Tier C script env vars"
```

---

### Task 3: `LyricsMatchValidator`

**Files:**

- Create: `Sources/LyricsRepository/LyricsMatchValidator.swift`
- Test: `Tests/LyricsRepositoryTests/LyricsMatchValidatorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/LyricsRepositoryTests/LyricsMatchValidatorTests.swift`:

```swift
import Domain
import Testing

@testable import LyricsRepository

@Suite("LyricsMatchValidator")
struct LyricsMatchValidatorTests {
    let validator = LyricsMatchValidator()

    @Test("exact title and duration match is valid")
    func exactMatch() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "Shape of You", artistName: "Ed Sheeran", duration: 233, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("wildly different title is invalid")
    func differentTitleInvalid() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "Bohemian Rhapsody", artistName: "Queen", duration: 233, plainLyrics: "lyrics")
        #expect(!validator.isValid(candidate: candidate, result: result))
    }

    @Test("duration far outside tolerance is invalid even when title matches")
    func durationMismatchInvalid() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "Shape of You", artistName: "Ed Sheeran", duration: 400, plainLyrics: "lyrics")
        #expect(!validator.isValid(candidate: candidate, result: result))
    }

    @Test("duration within tolerance is valid")
    func durationWithinToleranceValid() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "Shape of You", artistName: "Ed Sheeran", duration: 236, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("missing trackName on result skips title check")
    func missingTrackNameSkipsTitleCheck() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(duration: 233, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("missing duration on either side skips duration check")
    func missingDurationSkipsDurationCheck() {
        let candidate = Track(title: "Shape of You", artist: "Ed Sheeran")
        let result = LyricsResult(trackName: "Shape of You", artistName: "Ed Sheeran", plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }

    @Test("case and punctuation differences do not affect title match")
    func caseAndPunctuationIgnored() {
        let candidate = Track(title: "Shape of You!", artist: "Ed Sheeran", duration: 233)
        let result = LyricsResult(trackName: "shape of you", artistName: "Ed Sheeran", duration: 233, plainLyrics: "lyrics")
        #expect(validator.isValid(candidate: candidate, result: result))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LyricsMatchValidatorTests`
Expected: FAIL — `LyricsMatchValidator` does not exist (compile error).

- [ ] **Step 3: Implement `LyricsMatchValidator`**

Create `Sources/LyricsRepository/LyricsMatchValidator.swift`:

```swift
struct LyricsMatchValidator {
    let titleSimilarityThreshold: Double
    let durationToleranceSeconds: Double

    init(titleSimilarityThreshold: Double = 0.6, durationToleranceSeconds: Double = 5) {
        self.titleSimilarityThreshold = titleSimilarityThreshold
        self.durationToleranceSeconds = durationToleranceSeconds
    }

    func isValid(candidate: Track, result: LyricsResult) -> Bool {
        titleMatches(candidate: candidate, result: result) && durationMatches(candidate: candidate, result: result)
    }
}

extension LyricsMatchValidator {
    private func titleMatches(candidate: Track, result: LyricsResult) -> Bool {
        guard let resultTitle = result.trackName, !resultTitle.isEmpty else { return true }
        return Self.similarity(Self.normalized(candidate.title), Self.normalized(resultTitle)) >= titleSimilarityThreshold
    }

    private func durationMatches(candidate: Track, result: LyricsResult) -> Bool {
        guard let candidateDuration = candidate.duration, let resultDuration = result.duration else { return true }
        return abs(candidateDuration - resultDuration) <= durationToleranceSeconds
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        let maxLength = max(a.count, b.count)
        guard maxLength > 0 else { return 1 }
        let distance = levenshteinDistance(Array(a), Array(b))
        return 1 - Double(distance) / Double(maxLength)
    }

    private static func levenshteinDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, charA) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, charB) in b.enumerated() {
                current[j + 1] = charA == charB ? previous[j] : 1 + min(previous[j], previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }
}
```

Note: `Track.duration` is in seconds (`TimeInterval`) and `LyricsResult.duration` is `Double` in seconds (LRCLIB's convention) — both already comparable without unit conversion, matching how `LyricsDataSourceImpl.get()` already passes `duration.map(Int.init)` straight through to the LRCLIB API.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LyricsMatchValidatorTests`
Expected: PASS (all 7 cases green).

- [ ] **Step 5: Commit**

```bash
git add Sources/LyricsRepository/LyricsMatchValidator.swift Tests/LyricsRepositoryTests/LyricsMatchValidatorTests.swift
git commit -m "feat(#308): add LyricsMatchValidator for Tier B/C title+duration validation"
```

---

### Task 4: Fix `MetadataRepositoryImpl.resolve()` (bug 1 — LLM cache short-circuit)

**Files:**

- Modify: `Sources/MetadataRepository/MetadataRepositoryImpl.swift`
- Modify: `Tests/MetadataRepositoryTests/MetadataRepositoryTests.swift`

- [ ] **Step 1: Replace the existing tests that assert the old short-circuit behavior**

Replace the full contents of `Tests/MetadataRepositoryTests/MetadataRepositoryTests.swift` with:

```swift
import Dependencies
import Domain
import Foundation
import Testing

@testable import MetadataRepository

// MARK: - Cache behavior

@Suite("LLM cache")
struct LLMCacheTests {
    @Test("cache hit still queries MusicBrainz and Regex, raw track appended last")
    func cacheHitStillQueriesOtherSources() async {
        let cached = Track(title: "Cached", artist: "Artist")
        let mbTracker = CallTracker()
        let regexTracker = CallTracker()

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore(result: cached)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = TrackingDataSource<MusicBrainzMetadata>(tracker: mbTracker)
            $0.regexMetadataDataSource = TrackingDataSource<Track>(tracker: regexTracker)
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [cached, raw])
            let mbCalled = await mbTracker.called
            let regexCalled = await regexTracker.called
            #expect(mbCalled, "MusicBrainz must still be queried even when the LLM cache hits")
            #expect(regexCalled, "Regex must still be queried even when the LLM cache hits")
        }
    }
}

@Suite("MusicBrainz cache")
struct MusicBrainzCacheTests {
    @Test("returns cached MusicBrainzMetadata converted to Track, still queries Regex, raw appended")
    func mbCacheHitAfterLLMFail() async {
        let metadata = MusicBrainzMetadata(title: "MB Title", artist: "MB Artist", duration: 240, musicbrainzId: "abc-123")

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore(result: metadata)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [Track(title: "MB Title", artist: "MB Artist", duration: 240), raw])
        }
    }
}

// MARK: - DataSource merging

@Suite("DataSource merging")
struct DataSourceMergingTests {
    @Test("all sources are queried and merged in LLM > MusicBrainz > Regex > raw order")
    func allSourcesQueriedAndMerged() async {
        let mbMetadata = MusicBrainzMetadata(title: "MB", artist: "B", duration: nil, musicbrainzId: "id-1")

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource(candidates: [Track(title: "LLM", artist: "A")])
            $0.musicBrainzMetadataDataSource = StubDataSource(candidates: [mbMetadata])
            $0.regexMetadataDataSource = StubDataSource(candidates: [Track(title: "Regex", artist: "C")])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(
                result == [
                    Track(title: "LLM", artist: "A"),
                    Track(title: "MB", artist: "B"),
                    Track(title: "Regex", artist: "C"),
                    raw,
                ])
        }
    }

    @Test("falls back to Regex when LLM and MusicBrainz both fail, raw still appended")
    func regexFallback() async {
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource(candidates: [Track(title: "Regex", artist: "C")])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [Track(title: "Regex", artist: "C"), raw])
        }
    }

    @Test("raw track is the sole result when all sources fail")
    func rawOnlyWhenAllSourcesFail() async {
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [raw])
        }
    }
}

// MARK: - Cache write behavior

@Suite("cache write")
struct CacheWriteTests {
    @Test("LLM success writes to AI cache")
    func llmWritesToAICache() async {
        let store = RecordingDataStore<Track>()

        await withDependencies {
            $0.llmMetadataDataStore = store
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource(candidates: [Track(title: "LLM", artist: "A")])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            _ = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            let written = await store.writtenValue
            #expect(written == Track(title: "LLM", artist: "A"))
        }
    }

    @Test("MusicBrainz success writes to MusicBrainz cache")
    func mbWritesToMBCache() async {
        let store = RecordingDataStore<MusicBrainzMetadata>()
        let metadata = MusicBrainzMetadata(title: "Song", artist: "B", duration: 180, musicbrainzId: "xyz")

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = store
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource(candidates: [metadata])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            _ = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            let written = await store.writtenValue
            #expect(written == metadata)
        }
    }

    @Test("Regex results are not cached")
    func regexNotCached() async {
        let aiStore = RecordingDataStore<Track>()
        let mbStore = RecordingDataStore<MusicBrainzMetadata>()

        await withDependencies {
            $0.llmMetadataDataStore = aiStore
            $0.musicBrainzMetadataDataStore = mbStore
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource(candidates: [Track(title: "Regex", artist: "C")])
        } operation: {
            let repo = MetadataRepositoryImpl()
            _ = await repo.resolve(track: Track(title: "raw", artist: "raw"))
            let aiWritten = await aiStore.writtenValue
            let mbWritten = await mbStore.writtenValue
            #expect(aiWritten == nil)
            #expect(mbWritten == nil)
        }
    }
}

// MARK: - Type conversion

@Suite("type conversion")
struct TypeConversionTests {
    @Test("MusicBrainzMetadata converts to Track using title and artist only, raw appended")
    func mbToTrackConversion() async {
        let metadata = MusicBrainzMetadata(title: "Song", artist: "Artist", duration: 300, musicbrainzId: "id-999")

        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource(candidates: [metadata])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let raw = Track(title: "raw", artist: "raw")
            let result = await repo.resolve(track: raw)
            #expect(result == [Track(title: "Song", artist: "Artist", duration: 300), raw])
        }
    }
}

// MARK: - isAIMetadataCached

@Suite("isAIMetadataCached")
struct IsAIMetadataCachedTests {
    @Test("returns true when the LLM cache holds a value")
    func cachedReturnsTrue() async {
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore(result: Track(title: "Cached", artist: "Artist"))
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = StubDataSource<Track>(candidates: [])
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let cached = await repo.isAIMetadataCached(track: Track(title: "raw", artist: "raw"))
            #expect(cached)
        }
    }

    @Test("returns false when the LLM cache is empty — no DataSource is consulted")
    func uncachedReturnsFalse() async {
        let llmTracker = CallTracker()
        await withDependencies {
            $0.llmMetadataDataStore = StubMetadataDataStore<Track>(result: nil)
            $0.musicBrainzMetadataDataStore = StubMetadataDataStore<MusicBrainzMetadata>(result: nil)
            $0.llmMetadataDataSource = TrackingDataSource<Track>(tracker: llmTracker)
            $0.musicBrainzMetadataDataSource = StubDataSource<MusicBrainzMetadata>(candidates: [])
            $0.regexMetadataDataSource = StubDataSource<Track>(candidates: [])
        } operation: {
            let repo = MetadataRepositoryImpl()
            let cached = await repo.isAIMetadataCached(track: Track(title: "raw", artist: "raw"))
            #expect(!cached)
            let llmCalled = await llmTracker.called
            #expect(!llmCalled, "isAIMetadataCached must only read the cache, never invoke the DataSource")
        }
    }
}

// MARK: - Test helpers

private struct StubMetadataDataStore<Value: Sendable & Equatable>: MetadataDataStore {
    let result: Value?
    func read(title: String, artist: String) async -> Value? { result }
    func write(title: String, artist: String, value: Value) async throws {}
}

private actor RecordingDataStore<Value: Sendable & Equatable>: MetadataDataStore {
    private(set) var writtenValue: Value?
    func read(title: String, artist: String) async -> Value? { nil }
    func write(title: String, artist: String, value: Value) async throws { writtenValue = value }
}

private struct StubDataSource<Value: Sendable>: MetadataDataSource {
    let candidates: [Value]
    func resolve(track: Track) async -> [Value] { candidates }
}

private actor CallTracker {
    private(set) var called = false
    func markCalled() { called = true }
}

private struct TrackingDataSource<Value: Sendable>: MetadataDataSource {
    let tracker: CallTracker
    func resolve(track: Track) async -> [Value] {
        await tracker.markCalled()
        return []
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MetadataRepositoryTests`
Expected: FAIL — e.g. `cacheHitStillQueriesOtherSources` fails because the current `resolve()` short-circuits on LLM cache hit and never touches MusicBrainz/Regex; `rawOnlyWhenAllSourcesFail` fails because current `resolve()` returns `[]`, not `[raw]`.

- [ ] **Step 3: Rewrite `MetadataRepositoryImpl.resolve()`**

Replace the full contents of `Sources/MetadataRepository/MetadataRepositoryImpl.swift`:

```swift
import Dependencies
import Domain

public struct MetadataRepositoryImpl {
    @Dependency(\.llmMetadataDataSource) private var llmDataSource
    @Dependency(\.musicBrainzMetadataDataSource) private var musicBrainzDataSource
    @Dependency(\.regexMetadataDataSource) private var regexDataSource
    @Dependency(\.llmMetadataDataStore) private var llmDataStore
    @Dependency(\.musicBrainzMetadataDataStore) private var musicBrainzDataStore

    public init() {}
}

extension MetadataRepositoryImpl: MetadataRepository {
    public func resolve(track: Track) async -> [Track] {
        let llmCandidates = await resolveLLM(track: track)
        let mbCandidates = await resolveMusicBrainz(track: track)
        let regexCandidates = await regexDataSource.resolve(track: track).map {
            Track(title: $0.title, artist: $0.artist, duration: track.duration)
        }
        return llmCandidates + mbCandidates + regexCandidates + [track]
    }

    public func isAIMetadataCached(track: Track) async -> Bool {
        await llmDataStore.read(title: track.title, artist: track.artist) != nil
    }
}

// MARK: - Private

extension MetadataRepositoryImpl {
    private func resolveLLM(track: Track) async -> [Track] {
        if let cached = await llmDataStore.read(title: track.title, artist: track.artist) {
            return [Track(title: cached.title, artist: cached.artist, duration: track.duration)]
        }
        let candidates = await llmDataSource.resolve(track: track)
        if let first = candidates.first {
            try? await llmDataStore.write(title: track.title, artist: track.artist, value: first)
        }
        return candidates.map { Track(title: $0.title, artist: $0.artist, duration: track.duration) }
    }

    private func resolveMusicBrainz(track: Track) async -> [Track] {
        if let cached = await musicBrainzDataStore.read(title: track.title, artist: track.artist) {
            return [Track(title: cached.title, artist: cached.artist, duration: cached.duration)]
        }
        let candidates = await musicBrainzDataSource.resolve(track: track)
        if let first = candidates.first {
            try? await musicBrainzDataStore.write(title: track.title, artist: track.artist, value: first)
        }
        return candidates.map { Track(title: $0.title, artist: $0.artist, duration: $0.duration) }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MetadataRepositoryTests`
Expected: PASS (all suites green).

- [ ] **Step 5: Run the dependent `MetadataUseCaseTests` to confirm no regression**

Run: `swift test --filter MetadataUseCaseTests`
Expected: PASS — these tests use a hand-written `MockMetadataRepository` (not `MetadataRepositoryImpl`), so they are unaffected by this change.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetadataRepository/MetadataRepositoryImpl.swift Tests/MetadataRepositoryTests/MetadataRepositoryTests.swift
git commit -m "fix(#308): MetadataRepositoryImpl no longer short-circuits on LLM cache hit (bug 1)"
```

---

### Task 5: Add `customScriptLyricsDataSource` DI key

**Files:**

- Modify: `Sources/Domain/DataSource/LyricsDataSource.swift`

- [ ] **Step 1: Add the second DI key**

Edit `Sources/Domain/DataSource/LyricsDataSource.swift` to its full new contents:

```swift
import Dependencies
import Foundation

public protocol LyricsDataSource: Sendable {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult?
    func search(query: String) async -> [LyricsResult]?
}

public enum LyricsDataSourceKey: TestDependencyKey {
    public static let testValue: any LyricsDataSource = UnimplementedLyricsDataSource()
}

public enum CustomScriptLyricsDataSourceKey: TestDependencyKey {
    public static let testValue: any LyricsDataSource = UnimplementedLyricsDataSource()
}

extension DependencyValues {
    public var lyricsDataSource: any LyricsDataSource {
        get { self[LyricsDataSourceKey.self] }
        set { self[LyricsDataSourceKey.self] = newValue }
    }

    public var customScriptLyricsDataSource: any LyricsDataSource {
        get { self[CustomScriptLyricsDataSourceKey.self] }
        set { self[CustomScriptLyricsDataSourceKey.self] = newValue }
    }
}

private struct UnimplementedLyricsDataSource: LyricsDataSource {
    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { nil }
    func search(query: String) async -> [LyricsResult]? { nil }
}
```

This is not independently testable (it is DI wiring, mirroring the `llmMetadataDataSource`/`regexMetadataDataSource` two-keys-one-protocol precedent already in `Domain/DataSource/MetadataDataSource.swift`) — verified instead by Task 8's `LyricsRepositoryImpl` tests, which inject `$0.customScriptLyricsDataSource`.

- [ ] **Step 2: Build to verify no compile errors**

Run: `swift build --target Domain`
Expected: builds cleanly.

- [ ] **Step 3: Commit**

```bash
git add Sources/Domain/DataSource/LyricsDataSource.swift
git commit -m "feat(#308): add customScriptLyricsDataSource DI key for Tier C"
```

---

### Task 6: `CustomScriptLyricsDataSourceImpl` (Tier C)

**Files:**

- Create: `Sources/LyricsDataSource/CustomScriptLyricsDataSourceImpl.swift`
- Test: `Tests/LyricsDataSourceTests/CustomScriptLyricsDataSourceImplTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/LyricsDataSourceTests/CustomScriptLyricsDataSourceImplTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CustomScriptLyricsDataSourceImplTests`
Expected: FAIL — `CustomScriptLyricsDataSourceImpl` does not exist (compile error).

- [ ] **Step 3: Implement `CustomScriptLyricsDataSourceImpl`**

Create `Sources/LyricsDataSource/CustomScriptLyricsDataSourceImpl.swift`:

```swift
import Dependencies
import Domain
import Foundation
import os

public struct CustomScriptLyricsDataSourceImpl: Sendable {
    private let fallbackCommand: [String]
    private let timeoutMs: Double
    private let configDir: String
    private let cacheDir: String
    let processRunner: @Sendable (String, [String], [String: String], Double) async throws -> (
        status: Int32, stdout: String, stderr: String
    )

    public init() {
        @Dependency(\.configDataSource) var configDataSource
        let lyrics = configDataSource.load()?.config.lyrics
        self.init(
            fallbackCommand: lyrics?.fallbackCommand ?? [],
            timeoutMs: lyrics?.timeoutMs.value ?? 5000,
            configDir: configDataSource.configDir,
            cacheDir: Self.resolvedCacheDir(),
            processRunner: { executable, arguments, environment, timeoutMs in
                try await Self.executeProcess(
                    executable: executable, arguments: arguments, environment: environment, timeoutMs: timeoutMs)
            }
        )
    }

    init(
        fallbackCommand: [String],
        timeoutMs: Double,
        configDir: String,
        cacheDir: String,
        processRunner: @escaping @Sendable (String, [String], [String: String], Double) async throws -> (
            status: Int32, stdout: String, stderr: String
        )
    ) {
        self.fallbackCommand = fallbackCommand
        self.timeoutMs = timeoutMs
        self.configDir = configDir
        self.cacheDir = cacheDir
        self.processRunner = processRunner
    }

    private static func resolvedCacheDir() -> String {
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
        guard let executable = fallbackCommand.first else { return nil }
        let arguments = Array(fallbackCommand.dropFirst()) + [title, artist]
        let environment = ["LYRA_CONFIG_DIR": configDir, "LYRA_CACHE_DIR": cacheDir]

        guard let (status, stdout, _) = try? await processRunner(executable, arguments, environment, timeoutMs),
            status == 0,
            let data = stdout.data(using: .utf8),
            let output = try? JSONDecoder().decode(ScriptOutput.self, from: data),
            let plainLyrics = output.plainLyrics, !plainLyrics.isEmpty
        else { return nil }

        return LyricsResult(trackName: output.trackName, artistName: output.artistName, plainLyrics: plainLyrics)
    }

    public func search(query: String) async -> [LyricsResult]? { nil }
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

// MARK: - Async Process

extension CustomScriptLyricsDataSourceImpl {
    static func executeProcess(
        executable: String, arguments: [String], environment: [String: String], timeoutMs: Double
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            let buffer = ScriptProcessBuffer()
            let group = DispatchGroup()
            let hasResumed = OSAllocatedUnfairLock(initialState: false)

            group.enter()
            DispatchQueue.global().async {
                buffer.stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                buffer.stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            let timeoutWorkItem = DispatchWorkItem {
                let shouldResume = hasResumed.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                guard shouldResume else { return }
                process.terminate()
                continuation.resume(returning: (-1, "", "timed out after \(Int(timeoutMs))ms"))
            }
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .milliseconds(Int(timeoutMs)), execute: timeoutWorkItem)

            group.notify(queue: .global()) {
                let shouldResume = hasResumed.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                guard shouldResume else { return }
                timeoutWorkItem.cancel()
                process.waitUntilExit()
                continuation.resume(
                    returning: (process.terminationStatus, buffer.stdoutTrimmed, buffer.stderrTrimmed))
            }
        }
    }
}

/// Accumulates stdout/stderr from concurrent pipe-drain tasks. `@unchecked Sendable`
/// because each property is written by exactly one DispatchQueue task and read only
/// after the DispatchGroup barrier — no lock needed (mirrors YouTubeWallpaperDataSourceImpl's PipeBuffer).
private final class ScriptProcessBuffer: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()

    var stdoutTrimmed: String { trimmed(stdout) }
    var stderrTrimmed: String { trimmed(stderr) }

    private func trimmed(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CustomScriptLyricsDataSourceImplTests`
Expected: PASS (all 8 cases green).

- [ ] **Step 5: Commit**

```bash
git add Sources/LyricsDataSource/CustomScriptLyricsDataSourceImpl.swift Tests/LyricsDataSourceTests/CustomScriptLyricsDataSourceImplTests.swift
git commit -m "feat(#308): CustomScriptLyricsDataSourceImpl — Tier C user script invocation"
```

---

### Task 7: DI registration for Tier C

**Files:**

- Modify: `Sources/DependencyInjection/DataSourceRegistration.swift`

- [ ] **Step 1: Register the live value**

Edit `Sources/DependencyInjection/DataSourceRegistration.swift` — find the existing block:

```swift
extension LyricsDataSourceKey: DependencyKey {
    public static let liveValue: any LyricsDataSource = LyricsDataSourceImpl()
}
```

Add directly after it:

```swift
extension CustomScriptLyricsDataSourceKey: DependencyKey {
    public static let liveValue: any LyricsDataSource = CustomScriptLyricsDataSourceImpl()
}
```

- [ ] **Step 2: Build to verify no compile errors**

Run: `swift build --target DependencyInjection`
Expected: builds cleanly.

- [ ] **Step 3: Commit**

```bash
git add Sources/DependencyInjection/DataSourceRegistration.swift
git commit -m "feat(#308): wire CustomScriptLyricsDataSourceImpl as the live Tier C data source"
```

---

### Task 8: Fix `LyricsRepositoryImpl.fetchLyrics(candidates:)` (bug 2 + Tier B validation + Tier C)

**Files:**

- Modify: `Sources/LyricsRepository/LyricsRepositoryImpl.swift`
- Modify: `Tests/LyricsRepositoryTests/LyricsRepositoryTests.swift`

- [ ] **Step 1: Add failing tests for the cache-key fix and Tier B/C behavior**

Add to `Tests/LyricsRepositoryTests/LyricsRepositoryTests.swift`, inside the `CandidatesFetch` suite (after the existing `fallsBackToMatchedCandidate` test, before the closing brace of the suite):

```swift
        @Test("Tier A cache write is keyed by the matched candidate, not candidates.first")
        func cacheWriteKeyedByMatchedCandidateTierA() async {
            let lrclibResult = LyricsResult(plainLyrics: "Lyrics body")
            let spy = KeyCapturingLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = StubLyricsDataSource(
                    getHandler: { _, artist, _ in
                        artist == "Real Artist" ? lrclibResult : nil
                    })
            } operation: {
                let repo = LyricsRepositoryImpl()
                _ = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                let key = await spy.lastWriteKey
                #expect(key?.title == "Real Title")
                #expect(key?.artist == "Real Artist")
            }
        }

        @Test("Tier B (search) validates title similarity and caches under the matched candidate")
        func tierBValidatesAndCachesMatchedCandidate() async {
            let validResult = LyricsResult(trackName: "Real Title", artistName: "Real Artist", syncedLyrics: "[00:01.00] Line")
            let spy = KeyCapturingLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = QueryMatchingSearchDataSource(
                    getResult: nil,
                    resultsByQuery: ["Real Title Real Artist": [validResult]]
                )
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                #expect(result?.syncedLyrics == "[00:01.00] Line")
                let key = await spy.lastWriteKey
                #expect(key?.title == "Real Title")
                #expect(key?.artist == "Real Artist")
            }
        }

        @Test("Tier B rejects a search result whose title is wildly different from the candidate")
        func tierBRejectsMismatchedTitle() async {
            let mismatchedResult = LyricsResult(trackName: "Completely Different Song", artistName: "Someone Else", plainLyrics: "wrong lyrics")

            await withDependencies {
                $0.lyricsCache = StubLyricsCache(stored: nil)
                $0.lyricsDataSource = QueryMatchingSearchDataSource(
                    getResult: nil,
                    resultsByQuery: ["My Title My Artist": [mismatchedResult]]
                )
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "My Title", artist: "My Artist")
                ])
                #expect(result == nil, "a title-mismatched search result must not be accepted")
            }
        }

        @Test("Tier C is tried after Tier A/B fail, and its result is cached under the matched candidate")
        func tierCFallsBackAndCaches() async {
            let scriptResult = LyricsResult(trackName: "Real Title", artistName: "Real Artist", plainLyrics: "script lyrics")
            let spy = KeyCapturingLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.customScriptLyricsDataSource = StubLyricsDataSource(
                    getHandler: { _, artist, _ in
                        artist == "Real Artist" ? scriptResult : nil
                    })
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Garbled Title", artist: "Garbled Artist"),
                    Track(title: "Real Title", artist: "Real Artist"),
                ])
                #expect(result?.plainLyrics == "script lyrics")
                let key = await spy.lastWriteKey
                #expect(key?.title == "Real Title")
                #expect(key?.artist == "Real Artist")
            }
        }

        @Test("no cache write occurs when Tier A/B/C all fail")
        func noCacheWriteWhenAllTiersFail() async {
            let spy = KeyCapturingLyricsCache()

            await withDependencies {
                $0.lyricsCache = spy
                $0.lyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
                $0.customScriptLyricsDataSource = StubLyricsDataSource(getResult: nil, searchResult: nil)
            } operation: {
                let repo = LyricsRepositoryImpl()
                let result = await repo.fetchLyrics(candidates: [
                    Track(title: "Title", artist: "Artist")
                ])
                #expect(result == nil)
                let key = await spy.lastWriteKey
                #expect(key == nil)
            }
        }
```

Add these two new test helpers alongside the existing `// MARK: - Test helpers` section at the bottom of the file:

```swift
private actor KeyCapturingLyricsCache: LyricsDataStore {
    private(set) var lastWriteKey: (title: String, artist: String)?
    func read(title: String, artist: String) async -> LyricsResult? { nil }
    func write(title: String, artist: String, result: LyricsResult) async throws {
        lastWriteKey = (title, artist)
    }
}

private struct QueryMatchingSearchDataSource: LyricsDataSource {
    var getResult: LyricsResult?
    let resultsByQuery: [String: [LyricsResult]]

    func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? { getResult }
    func search(query: String) async -> [LyricsResult]? { resultsByQuery[query] }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LyricsRepositoryTests`
Expected: FAIL — `cacheWriteKeyedByMatchedCandidateTierA` fails (current code writes under `candidates.first`, i.e. "Garbled Title"/"Garbled Artist"); `tierBValidatesAndCachesMatchedCandidate`/`tierBRejectsMismatchedTitle` fail to compile (`customScriptLyricsDataSource` dependency not yet consumed, no validation exists); `tierCFallsBackAndCaches` fails (Tier C not wired).

- [ ] **Step 3: Rewrite `LyricsRepositoryImpl`**

Replace the full contents of `Sources/LyricsRepository/LyricsRepositoryImpl.swift`:

```swift
import Dependencies
import Domain
import Foundation

public struct LyricsRepositoryImpl {
    @Dependency(\.lyricsCache) private var cache
    @Dependency(\.lyricsDataSource) private var dataSource
    @Dependency(\.customScriptLyricsDataSource) private var customScriptDataSource
    private let validator = LyricsMatchValidator()

    public init() {}
}

extension LyricsRepositoryImpl: LyricsRepository {
    public func fetchLyrics(track: Track) async -> LyricsResult? {
        if let cached = await cache.read(title: track.title, artist: track.artist) {
            return cached
        }

        if let result = await dataSource.get(title: track.title, artist: track.artist, duration: track.duration) {
            await store(result, track: track)
            return result
        }

        let query = track.artist.isEmpty ? track.title : "\(track.title) \(track.artist)"
        if let results = await dataSource.search(query: query),
            let result = results.first(where: { $0.syncedLyrics != nil }) ?? results.first(where: { $0.plainLyrics != nil })
        {
            await store(result, track: track)
            return result
        }

        return nil
    }

    public func fetchLyrics(candidates: [Track]) async -> LyricsResult? {
        guard let first = candidates.first else { return nil }

        if let cached = await cache.read(title: first.title, artist: first.artist) {
            return cached
        }

        if let result = await tierAExactMatch(candidates: candidates) {
            return result
        }
        if let result = await tierBValidatedSearch(candidates: candidates) {
            return result
        }
        if let result = await tierCCustomScript(candidates: candidates) {
            return result
        }
        return nil
    }
}

// MARK: - Tier A: LRCLIB exact match

extension LyricsRepositoryImpl {
    private func tierAExactMatch(candidates: [Track]) async -> LyricsResult? {
        for c in candidates where !c.artist.isEmpty {
            guard let result = await dataSource.get(title: c.title, artist: c.artist, duration: c.duration) else { continue }
            let displayResult = displayAdjusted(result, candidate: c)
            await store(displayResult, track: c)
            return displayResult
        }
        return nil
    }
}

// MARK: - Tier B: LRCLIB fuzzy search + validation

extension LyricsRepositoryImpl {
    private func tierBValidatedSearch(candidates: [Track]) async -> LyricsResult? {
        for c in candidates {
            let query = c.artist.isEmpty ? c.title : "\(c.title) \(c.artist)"
            guard let responses = await dataSource.search(query: query) else { continue }
            guard
                let matched = responses.first(where: { $0.syncedLyrics != nil })
                    ?? responses.first(where: { $0.plainLyrics != nil })
            else { continue }
            guard validator.isValid(candidate: c, result: matched) else { continue }
            let displayResult = displayAdjusted(matched, candidate: c)
            await store(displayResult, track: c)
            return displayResult
        }
        return nil
    }
}

// MARK: - Tier C: user-defined custom script

extension LyricsRepositoryImpl {
    private func tierCCustomScript(candidates: [Track]) async -> LyricsResult? {
        for c in candidates where !c.artist.isEmpty {
            guard let result = await customScriptDataSource.get(title: c.title, artist: c.artist, duration: c.duration) else {
                continue
            }
            guard validator.isValid(candidate: c, result: result) else { continue }
            let displayResult = displayAdjusted(result, candidate: c)
            await store(displayResult, track: c)
            return displayResult
        }
        return nil
    }
}

// MARK: - Private

extension LyricsRepositoryImpl {
    private func displayAdjusted(_ result: LyricsResult, candidate: Track) -> LyricsResult {
        (result.trackName?.isEmpty ?? true) ? result.withDisplay(title: candidate.title, artist: candidate.artist) : result
    }

    private func store(_ result: LyricsResult, track: Track) async {
        guard !track.artist.isEmpty else { return }
        try? await cache.write(title: track.title, artist: track.artist, result: result)
    }
}
```

Note: `dataSource.get` here is a single-value LRCLIB call keyed to `(title, artist, duration)` — LRCLIB's own exact-match semantics are the Tier A trust boundary (per the approved spec, Tier A needs no additional validator). Only Tier B (fuzzy `.search()`) and Tier C (user script, no duration signal) run through `LyricsMatchValidator`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LyricsRepositoryTests`
Expected: PASS (all new and existing tests green).

- [ ] **Step 5: Run the sibling edge-case suite to confirm no regression**

Run: `swift test --filter LyricsRepositoryEdgeCaseTests`
Expected: PASS — `candidatesSearchFallbackAcrossAll`/`candidatesPreservesLRCLIBDisplay`/etc. use stub results without `trackName`/`duration` populated on the Tier B path, so the new validator's guards (`guard let resultTitle = result.trackName ... else return true`, `guard let candidateDuration ... else return true`) trivially pass and behavior is unchanged.

- [ ] **Step 6: Run the full test suite once for this module boundary**

Run: `swift test --filter LyricsRepository`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/LyricsRepository/LyricsRepositoryImpl.swift Tests/LyricsRepositoryTests/LyricsRepositoryTests.swift
git commit -m "fix(#308): LyricsRepositoryImpl caches under the matched candidate (bug 2), adds Tier B validation + Tier C"
```

---

### Task 9: Fix `TrackInteractorImpl` display fallback

**Files:**

- Modify: `Sources/TrackInteractor/TrackInteractorImpl.swift`
- Test: `Tests/TrackInteractorTests/TrackInteractorFallbackDisplayTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/TrackInteractorTests/TrackInteractorFallbackDisplayTests.swift`:

```swift
@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import TrackInteractor

// MARK: - Stubs

private final class StubPlaybackUseCase: PlaybackUseCase, @unchecked Sendable {
    let subject = CurrentValueSubject<NowPlaying?, Never>(nil)

    func fetchNowPlaying() async -> NowPlaying? { nil }

    func observeNowPlaying() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            let cancellable = subject.sink(
                receiveCompletion: { _ in continuation.finish() },
                receiveValue: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func elapsedTime(for np: NowPlaying) -> TimeInterval? { np.rawElapsed }
}

private struct GuessingMetadataUseCase: MetadataUseCase, Sendable {
    func resolve(track: Track) async -> Track? { Track(title: "Wrong Guess", artist: "Wrong Artist") }
    func resolveCandidates(track: Track) async -> [Track] { [Track(title: "Wrong Guess", artist: "Wrong Artist")] }
    func isAIMetadataCached(track: Track) async -> Bool { true }
}

private struct NotFoundLyricsUseCase: LyricsUseCase, Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult { LyricsResult() }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult { LyricsResult() }
    func parseLyricsContent(from result: LyricsResult?) -> LyricsContent? { nil }
}

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var appStyle: AppStyle { .init() }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

// MARK: - Helpers

private final class TrackUpdateCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [TrackUpdate] = []

    var snapshot: [TrackUpdate] { lock.withLock { updates } }

    func append(_ update: TrackUpdate) { lock.withLock { updates.append(update) } }

    func waitForCount(_ target: Int, timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while snapshot.count < target, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private func makeInteractor(playback: StubPlaybackUseCase) -> TrackInteractorImpl {
    withDependencies {
        $0.continuousClock = ImmediateClock()
        $0.playbackUseCase = playback
        $0.metadataUseCase = GuessingMetadataUseCase()
        $0.lyricsUseCase = NotFoundLyricsUseCase()
        $0.configUseCase = StubConfigUseCase()
    } operation: {
        TrackInteractorImpl()
    }
}

private func nowPlaying(title: String?, artist: String?) -> NowPlaying {
    NowPlaying(
        title: title, artist: artist, artworkData: nil,
        duration: nil, rawElapsed: nil, playbackRate: 1, timestamp: nil
    )
}

// MARK: - Tests

@Suite("TrackInteractor display fallback", .serialized)
struct TrackInteractorFallbackDisplayTests {
    @Test("falls back to raw title/artist, not the unvalidated candidate guess, when lyrics are not found")
    func fallsBackToRawWhenLyricsNotFound() async {
        let playback = StubPlaybackUseCase()
        let interactor = makeInteractor(playback: playback)
        let collector = TrackUpdateCollector()
        let cancellable = interactor.trackChange.sink { collector.append($0) }
        defer { cancellable.cancel() }

        playback.subject.send(nowPlaying(title: "Raw Title", artist: "Raw Artist"))
        await collector.waitForCount(3)

        let final = collector.snapshot.last
        #expect(final?.title == "Raw Title")
        #expect(final?.artist == "Raw Artist")
        #expect(final?.lyricsState == .notFound)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TrackInteractorFallbackDisplayTests`
Expected: FAIL — current code falls back to `resolvedTitle`/`resolvedArtist` ("Wrong Guess"/"Wrong Artist"), not the raw `title`/`artist`.

- [ ] **Step 3: Fix the fallback in `TrackInteractorImpl.resolveTrack(from:)`**

Edit `Sources/TrackInteractor/TrackInteractorImpl.swift` — change these two lines (currently around line 209-210):

```swift
                                    let finalTitle = result.trackName ?? resolvedTitle
                                    let finalArtist = result.artistName ?? resolvedArtist
```

to:

```swift
                                    let finalTitle = result.trackName ?? title
                                    let finalArtist = result.artistName ?? artist
```

`title`/`artist` are the raw values already captured from `info.title`/`info.artist` at the top of `resolveTrack(from:)` (line 137), and are already in scope inside this closure via capture — no new parameters needed.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TrackInteractorFallbackDisplayTests`
Expected: PASS.

- [ ] **Step 5: Run the full `TrackInteractorTests` target to confirm no regression**

Run: `swift test --filter TrackInteractorTests`
Expected: PASS — none of the existing artwork/race/AI-processing/playback-position tests assert on `resolvedTitle`/`resolvedArtist` leaking into the final not-found state, so this change is additive.

- [ ] **Step 6: Commit**

```bash
git add Sources/TrackInteractor/TrackInteractorImpl.swift Tests/TrackInteractorTests/TrackInteractorFallbackDisplayTests.swift
git commit -m "fix(#308): TrackInteractor falls back to raw title/artist, not an unvalidated candidate guess"
```

---

### Task 10: README — Tier C documentation + utamap.com sample script

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Find the config documentation section**

Run: `grep -n "^\[ai\]\|^## Configuration\|^### " README.md | head -40`

Locate the existing `[ai]` config section (or the nearest equivalent optional-config-table documentation block) to match its heading level and format.

- [ ] **Step 2: Add the `[lyrics]` config section**

Add a new subsection immediately after the `[ai]` config documentation (same heading level), containing:

````markdown
### `[lyrics]` — Tier C custom lyrics fallback (optional)

When LRCLIB has no exact or fuzzy match for a track, lyra can shell out to a
user-defined script as a last resort before giving up and showing the raw
(unprocessed) title/artist:

```toml
[lyrics]
fallback_command = ["/usr/bin/python3", "/Users/you/.config/lyra/lyrics-fallback.py"]
timeout_ms = 5000
```

- `fallback_command` — an argv array (not a shell string). The first element
  must be an absolute path to the executable; lyra does not search `$PATH` for
  it (a `launchd`-run daemon has a minimal `PATH`, so relying on `$PATH`
  resolution would silently fail in production). If omitted, Tier C is
  skipped entirely.
- `timeout_ms` — how long lyra waits for the script before killing it and
  treating that candidate as a miss. Defaults to `5000`.

lyra invokes the script once per metadata candidate (raw title/artist, plus
any AI/MusicBrainz/regex-resolved guesses), appending `<title> <artist>` as
the final two arguments, and sets two read-only environment variables:

| Variable | Meaning |
|---|---|
| `LYRA_CONFIG_DIR` | The directory lyra actually loaded its config from. Setting this variable yourself has no effect on where lyra looks for its config — it is informational only. |
| `LYRA_CACHE_DIR` | The directory lyra uses for its own cache (`~/.cache/lyra` by default). Also informational only. |

The script must print a single line of JSON to stdout:

```json
{"track_name": "...", "artist_name": "...", "plain_lyrics": "..."}
```

lyra treats any of the following as "no match for this candidate" and moves
on to the next one: a non-zero exit code, unparseable JSON on stdout, or a
missing/empty `plain_lyrics` field. Whether your script signals "not found"
via a non-zero exit or an empty `plain_lyrics` is up to you — lyra handles
both identically.

#### Example: utamap.com scraper

This is a minimal example that scrapes [utamap.com](https://utamap.com) for
Japanese lyrics. It is not shipped with lyra — save it yourself and point
`fallback_command` at it:

```python
#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.parse
import re

def main():
    if len(sys.argv) < 3:
        sys.exit(1)
    title, artist = sys.argv[-2], sys.argv[-1]

    query = urllib.parse.quote(f"{title} {artist}")
    search_url = f"https://www.utamap.com/showkasi.php?surl={query}"

    try:
        with urllib.request.urlopen(search_url, timeout=4) as response:
            html = response.read().decode("utf-8", errors="ignore")
    except Exception:
        sys.exit(1)

    match = re.search(r'<div id="kasi">(.*?)</div>', html, re.DOTALL)
    if not match:
        sys.exit(1)

    lyrics = re.sub(r"<br\s*/?>", "\n", match.group(1))
    lyrics = re.sub(r"<[^>]+>", "", lyrics).strip()

    if not lyrics:
        sys.exit(1)

    print(json.dumps({
        "track_name": title,
        "artist_name": artist,
        "plain_lyrics": lyrics,
    }))

if __name__ == "__main__":
    main()
```

This example is illustrative only — utamap.com's actual HTML structure may
differ; inspect the page and adjust the scraping regex accordingly. lyra
ships no HTML-parsing code of its own for this site or any other.
````

- [ ] **Step 3: Verify markdown renders correctly**

Run: `grep -c '^```' README.md` — confirm the count is even (all fences closed).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(#308): document [lyrics] Tier C custom script config + utamap.com sample"
```

---

### Task 11: `CLAUDE.md` / `AGENTS.md` — Key Design Decisions entry

**Files:**

- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Add a Key Design Decisions entry to `CLAUDE.md`**

Add a new paragraph to the "Key Design Decisions" section (after the most recent existing entry, e.g. after the "#299" spectrum entries), following the same style as existing entries:

```markdown
**Confidence-based metadata+lyrics resolution (#308)**: `MetadataRepositoryImpl.resolve()` no longer short-circuits when the LLM cache/DataSource succeeds — LLM, MusicBrainz, and Regex are always all queried (cache-or-datasource per source) and merged (`llmCandidates + mbCandidates + regexCandidates + [rawTrack]`), so a bad LLM guess can no longer permanently starve the other sources from ever being tried. `LyricsRepositoryImpl.fetchLyrics(candidates:)` tries three tiers across *all* candidates before giving up — Tier A (`LyricsDataSource.get()`, LRCLIB's own exact match, trusted as-is), Tier B (`LyricsDataSource.search()` fuzzy match, now gated by the new `LyricsMatchValidator` — title similarity via normalized Levenshtein distance, plus duration tolerance when both sides have it), and Tier C (`customScriptLyricsDataSource`, a second `LyricsDataSource` DI key backed by `CustomScriptLyricsDataSourceImpl`, which shells out to a user-configured `[lyrics] fallback_command` argv array with a timeout, mirroring `YouTubeWallpaperDataSourceImpl`'s test-injectable `processRunner` pattern). Whichever tier validates first stores the result under *the matched candidate's* title/artist (fixing a latent bug where the cache was always keyed by `candidates.first` regardless of which candidate actually matched); `LyricsResult.trackName`/`artistName`/`withDisplay()` already carried enough shape to make the confirmed candidate's identity part of the cached lyrics entry itself, so no separate cross-repository "joint commit" coordinator was needed. When no tier validates, nothing is cached and `TrackInteractorImpl.resolveTrack(from:)` falls back to the raw (unprocessed) title/artist rather than an unvalidated candidate guess — a targeted 2-line fix, not a new orchestration layer.
```

- [ ] **Step 2: Mirror the summary in `AGENTS.md`**

Run: `grep -n "Key Design Decisions\|## " AGENTS.md | head -20` to find where AGENTS.md tracks equivalent content (per this repo's stated convention: "Keep the repository root AGENTS.md in sync when build/test commands, architecture boundaries, or workflow rules change"). Add a condensed version of the same paragraph (2-3 sentences) in the corresponding section of `AGENTS.md`, cross-referencing `CLAUDE.md` for the full detail if `AGENTS.md` already follows a "see CLAUDE.md for details" pattern elsewhere in the file.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs(#308): CLAUDE.md/AGENTS.md — confidence-based lyrics resolution design decision"
```

---

### Task 12: Full test suite + build verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: all tests PASS, including every suite touched in Tasks 1-9.

- [ ] **Step 2: Run the linter**

Run: `make lint`
Expected: no formatting violations. If violations are reported, run `make format` and re-verify with `make lint`, then commit the formatting fix separately:

```bash
git add -A
git commit -m "style(#308): swift-format pass"
```

- [ ] **Step 3: Release build sanity check**

Run: `swift build -c release`
Expected: builds cleanly with no warnings introduced by this feature's new files.

---

## Self-Review

**Spec coverage:**

- Bug 1 (LLM cache short-circuit) → Task 4. ✓
- Bug 2 (cache keyed by `candidates.first` instead of matched candidate) → Task 8. ✓
- Tier A unchanged (LRCLIB `.get()`, trusted as-is) → Task 8 (`tierAExactMatch`, no validator). ✓
- Tier B validation (title similarity + duration tolerance) → Task 3 (`LyricsMatchValidator`) + Task 8 (`tierBValidatedSearch`). ✓
- Tier C user-pluggable custom script (`fallback_command` argv array, `timeout_ms`, env vars, JSON contract, 3-way "no match" equivalence) → Tasks 1 (config), 5 (DI key), 6 (impl), 7 (registration), 8 (wiring). ✓
- `LYRA_CONFIG_DIR`/`LYRA_CACHE_DIR` as read-only informational env vars → Task 2 (`configDir`) + Task 6 (`cacheDir` resolution + env var wiring), documented as read-only in Task 10. ✓
- Raw-title/artist display fallback when nothing validates → Task 9. ✓
- No new SPM module / no `TrackResolutionCoordinator` (per the revised spec) → confirmed throughout File Structure; every new file lands in an existing target. ✓
- Security: argv-array only, no shell string interpolation → Task 6 (`Process.arguments`, no shell). ✓
- README Tier C docs + utamap.com sample → Task 10. ✓
- CLAUDE.md/AGENTS.md updates per `module-checklist.md` → Task 11. ✓

**Placeholder scan:** no "TBD"/"add appropriate error handling"/"similar to Task N" — every step above has complete, runnable code and exact file paths. The one intentionally-omitted test target (`Tests/EntityTests/LyricsConfigTests.swift`) is explicitly justified in File Structure (Entity is pure data, tested via decode tests instead) rather than left as a placeholder.

**Type/signature consistency:**

- `LyricsConfig(fallbackCommand:timeoutMs:)` (Task 1) matches the fields read in `CustomScriptLyricsDataSourceImpl.init()` (Task 6): `lyrics?.fallbackCommand`, `lyrics?.timeoutMs.value`.
- `ConfigDataSource.configDir: String` (Task 2) matches its use in `CustomScriptLyricsDataSourceImpl.init()` (Task 6): `configDataSource.configDir`.
- `CustomScriptLyricsDataSourceImpl`'s internal init signature (`fallbackCommand:timeoutMs:configDir:cacheDir:processRunner:`) is used identically across Task 6's tests and Task 6's own `init()`.
- `customScriptLyricsDataSource` DI key (Task 5) is consumed identically in `LyricsRepositoryImpl` (Task 8: `@Dependency(\.customScriptLyricsDataSource) private var customScriptDataSource`) and in tests (Task 8: `$0.customScriptLyricsDataSource = StubLyricsDataSource(...)`).
- `LyricsMatchValidator(titleSimilarityThreshold:durationToleranceSeconds:)` (Task 3) is instantiated with defaults (`private let validator = LyricsMatchValidator()`) in `LyricsRepositoryImpl` (Task 8) — matches the no-arg call convention used throughout Task 3's own tests.
- `TrackInteractorImpl`'s `title`/`artist` (raw, captured at `resolveTrack(from:)` entry) referenced in Task 9's fix are the same identifiers already in scope per the file excerpt read directly from the current source — not renamed or reintroduced.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-09-confidence-based-lyrics-resolution.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
