import Dependencies
import Domain
import Files
import Foundation
import TOMLKit
import os

public struct ConfigDataSourceImpl: Sendable {
    @Dependency(\.configWatchGateway) var watchGateway
    private let configHomeOverride: String?
    /// The last successfully decoded load, shared across value copies of this
    /// struct (the DI `liveValue` is a single long-lived instance). `load()`
    /// falls back to it while the on-disk config fails the *required* decode
    /// (broken TOML, malformed text/wallpaper section), so consumers that
    /// deliberately re-read per call — `[lyrics]` fallback_command, `[ai]`
    /// endpoint — keep honoring the last accepted config across a rejected
    /// hot-reload edit, mirroring `ConfigUseCase.reload()`'s keep-previous-style
    /// contract instead of silently degrading to defaults (#337 review).
    /// A malformed optional `[ai]`/`[lyrics]`/`[developer]` section alone is NOT
    /// protected: the lenient decode degrades it to `nil` and still succeeds, so
    /// the cache is overwritten — matching what `reload()` accepts (#330).
    private let lastGoodLoad = LastGoodLoadBox()

    public init(configHome: String? = nil) {
        configHomeOverride = configHome?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ConfigDataSourceImpl: ConfigDataSource {
    public func load() -> ConfigLoadResult? {
        guard let file = findConfigFile() else {
            // No config file at all: a deliberate removal means defaults, so the
            // last-good fallback must not outlive the file it came from.
            lastGoodLoad.value = nil
            return nil
        }
        let configDir = file.parent?.path ?? Folder.home.path
        guard let content = try? file.readAsString(),
            let config = decode(content: content, path: file.path, configDir: configDir)
        else {
            // The file exists but is unreadable or undecodable right now (a
            // rejected mid-edit state, or an atomic-save window): serve the last
            // accepted config so per-call readers keep working until it's fixed.
            return lastGoodLoad.value
        }
        let result = ConfigLoadResult(config: config, configDir: configDir)
        lastGoodLoad.value = result
        return result
    }

    public func template(format: ConfigFormat) -> String? {
        let config = AppConfig.defaults
        switch format {
        case .toml:
            guard let toml = try? TOMLEncoder().encode(config) else { return nil }
            return sanitizeTomlFloats(toml)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(config) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    public func writeTemplate(format: ConfigFormat, force: Bool) throws -> String {
        let configFolder = try lyraConfigFolder()
        let fileName = "config.\(format.fileExtension)"

        if !force, configFolder.containsFile(named: fileName) {
            let existing = try configFolder.file(named: fileName)
            throw ConfigWriteError.alreadyExists(path: existing.path)
        }

        guard let content = template(format: format) else {
            throw ConfigWriteError.encodingFailed
        }

        let file = try configFolder.createFile(named: fileName)
        try file.write(content)
        return file.path
    }

    public var existingConfigPath: String? {
        findConfigFile()?.path
    }

    public var configDir: String {
        // When the file exists, its parent; otherwise the directory where the config
        // *would* live, so the watcher can arm on it before the file is created (#329).
        findConfigFile()?.parent?.path ?? expectedConfigDirectory
    }

    public func tryDecode(strictOptionalSections: Bool) throws -> String {
        guard let file = findConfigFile(),
            let content = try? file.readAsString()
        else { return "" }
        let configDir = file.parent?.path ?? Folder.home.path
        // The required structure always gates validity — a malformed text /
        // wallpaper / spectrum section is fatal in either mode.
        try decodeOrThrow(content: content, path: file.path, configDir: configDir)
        // The optional [ai]/[lyrics] sections only gate validity in strict mode.
        // Hot-reload passes `false` so a malformed enhancement section degrades to
        // nil (matching startup) rather than discarding valid text/wallpaper edits.
        if strictOptionalSections {
            try strictDecodeOptionalSections(content: content, path: file.path, configDir: configDir)
        }
        return file.path
    }
}

/// Reference-type backing for the last-good load so every value copy of
/// `ConfigDataSourceImpl` shares one cache. `@unchecked Sendable`: all access
/// goes through the unfair lock.
private final class LastGoodLoadBox: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<ConfigLoadResult?>(initialState: nil)

    var value: ConfigLoadResult? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

extension ConfigDataSourceImpl {
    func findConfigFile() -> File? {
        let home = Folder.home
        let xdgConfigFolder: Folder? = {
            let explicit =
                configHomeOverride
                ?? ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]?.trimmingCharacters(
                    in: .whitespacesAndNewlines)
            guard let path = explicit, !path.isEmpty else {
                return try? home.subfolder(named: ".config")
            }
            return try? Folder(path: path)
        }()
        let lyraXdg = try? xdgConfigFolder?.subfolder(named: "lyra")
        // An explicit configHome override means "use exactly this config root" — skip the
        // legacy ~/.lyra fallback so an injected root stays hermetic (a real ~/.lyra on the
        // dev machine can't leak into tests). In production the override is nil, so ~/.lyra
        // is still searched as before.
        let lyraDot = configHomeOverride == nil ? (try? home.subfolder(named: ".lyra")) : nil
        let candidates: [(Folder?, String)] = [
            (lyraXdg, "config.toml"),
            (lyraDot, "config.toml"),
            (lyraXdg, "config.json"),
            (lyraDot, "config.json"),
        ]
        return candidates.lazy.compactMap { folder, name in
            try? folder?.file(named: name)
        }.first
    }

    // The directory where the config file lives or would live: `$XDG_CONFIG_HOME/lyra`,
    // falling back to `~/.config/lyra`. A pure path computation that never creates the
    // directory — the single source of truth shared by `configDir`'s file-absent fallback
    // (the watch target, #329) and `lyraConfigFolder()`'s create-and-open.
    var expectedConfigDirectory: String {
        let explicit =
            configHomeOverride
            ?? ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]?.trimmingCharacters(
                in: .whitespacesAndNewlines)
        let xdgConfigPath =
            (explicit?.isEmpty == false) ? explicit! : "\(Folder.home.path).config"
        return "\(xdgConfigPath)/lyra"
    }

    func lyraConfigFolder() throws -> Folder {
        let lyraPath = expectedConfigDirectory
        try FileManager.default.createDirectory(atPath: lyraPath, withIntermediateDirectories: true)
        return try Folder(path: lyraPath)
    }

    @discardableResult
    func decodeOrThrow(content: String, path: String, configDir: String) throws -> AppConfig {
        guard path.hasSuffix(".toml") else {
            return try JSONDecoder().decode(AppConfig.self, from: content.data(using: .utf8) ?? Data())
        }
        return try TOMLDecoder().decode(AppConfig.self, from: preparedTomlTable(content: content, configDir: configDir))
    }

    // Shared by decodeOrThrow and strictDecodeOptionalSections so include
    // resolution can never drift between actual loading and strict validation.
    func preparedTomlTable(content: String, configDir: String) throws -> TOMLTable {
        let table = try TOMLTable(string: content)
        resolveIncludes(into: table, configDir: configDir)
        table.remove(at: "includes")
        return table
    }

    func decode(content: String, path: String, configDir: String) -> AppConfig? {
        try? decodeOrThrow(content: content, path: path, configDir: configDir)
    }

    // [ai], [lyrics], and [developer] decode leniently at runtime (AppConfig.init
    // wraps them in try? so a malformed optional section degrades to nil instead of
    // taking down the user's entire visual config), which hides their shape errors
    // from decodeOrThrow. Validation must still surface them: probe the sections
    // strictly so `lyra healthcheck` reports a malformed [lyrics]/[ai]/[developer]
    // instead of the feature being silently disabled — e.g. `lyrics_resolution = "true"`
    // (string, not bool) would otherwise leave the trace quietly off.
    private struct StrictOptionalSections: Decodable {
        let ai: AIConfig?
        let lyrics: LyricsConfig?
        let developer: DeveloperConfig?
    }

    func strictDecodeOptionalSections(content: String, path: String, configDir: String) throws {
        guard path.hasSuffix(".toml") else {
            _ = try JSONDecoder().decode(StrictOptionalSections.self, from: content.data(using: .utf8) ?? Data())
            return
        }
        _ = try TOMLDecoder().decode(StrictOptionalSections.self, from: preparedTomlTable(content: content, configDir: configDir))
    }

    func resolveIncludes(into table: TOMLTable, configDir: String) {
        for file in includeFiles(of: table, configDir: configDir) {
            guard let content = try? file.readAsString(),
                let included = try? TOMLTable(string: content)
            else { continue }
            deepMerge(from: included, into: table)
        }
    }

    /// The config's current `includes` paths, re-resolved from the on-disk TOML
    /// each call WITHOUT requiring the files to exist. Feeds the hot-reload
    /// watch targets (ConfigWatch) through the same entry parsing decode uses,
    /// so the watched set can never drift from what decode would merge — and a
    /// missing include still contributes its parent directory to the watch, so
    /// creating the file later fires an event instead of going unnoticed.
    var includedConfigPaths: [String] {
        guard let file = findConfigFile(),
            file.path.hasSuffix(".toml"),  // `includes` is a TOML-only feature.
            let content = try? file.readAsString(),
            let table = try? TOMLTable(string: content)
        else { return [] }
        return includePaths(of: table, configDir: file.parent?.path ?? Folder.home.path)
    }

    // Shared entry parsing with includedConfigPaths, so watch targets can
    // never drift from what the decode actually merged.
    func includeFiles(of table: TOMLTable, configDir: String) -> [File] {
        includePaths(of: table, configDir: configDir).compactMap { try? File(path: $0) }
    }

    /// Absolute paths of the `includes` entries, resolved without touching the
    /// filesystem. Decode filters these down to existing files (`includeFiles`);
    /// the watch keeps them all.
    private func includePaths(of table: TOMLTable, configDir: String) -> [String] {
        guard let paths = table["includes"]?.array else { return [] }
        // Files-derived directory paths carry a trailing slash, but decode is
        // also called with plain caller-supplied strings — normalize the join.
        let base = configDir.hasSuffix("/") ? configDir : configDir + "/"
        return paths.compactMap { element in
            guard let path = element.string else { return nil }
            return path.hasPrefix("/") ? path : base + path
        }
    }

    func deepMerge(from source: TOMLTable, into target: TOMLTable) {
        for (key, value) in source {
            guard let sourceTable = value.table,
                let targetTable = target[key]?.table
            else {
                if target[key] == nil { target[key] = value }
                continue
            }
            deepMerge(from: sourceTable, into: targetTable)
        }
    }

    func sanitizeTomlFloats(_ toml: String) -> String {
        let pattern = #"(?<![0-9A-Za-z_.-])([0-9]+\.[0-9]{8,})(?![0-9A-Za-z_.-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return toml }
        let range = NSRange(toml.startIndex..<toml.endIndex, in: toml)
        var result = toml
        for match in regex.matches(in: toml, range: range).reversed() {
            guard let groupRange = Range(match.range(at: 1), in: result) else { continue }
            guard let value = Double(String(result[groupRange])) else { continue }
            result.replaceSubrange(groupRange, with: String(format: "%.15g", value))
        }
        return result
    }
}
