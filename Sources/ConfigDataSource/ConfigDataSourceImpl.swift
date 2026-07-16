import Domain
import Files
import Foundation
import TOMLKit

public struct ConfigDataSourceImpl: Sendable {
    private let configHomeOverride: String?

    public init(configHome: String? = nil) {
        configHomeOverride = configHome?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ConfigDataSourceImpl: ConfigDataSource {
    public func load() -> ConfigLoadResult? {
        guard let file = findConfigFile(),
            let content = try? file.readAsString()
        else { return nil }
        let configDir = file.parent?.path ?? Folder.home.path
        guard let config = decode(content: content, path: file.path, configDir: configDir) else { return nil }
        return ConfigLoadResult(config: config, configDir: configDir)
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

    // [ai] and [lyrics] decode leniently at runtime (AppConfig.init wraps them in
    // try? so a malformed optional enhancement section degrades to nil instead of
    // taking down the user's entire visual config), which hides their shape errors
    // from decodeOrThrow. Validation must still surface them: probe the two sections
    // strictly so `lyra healthcheck` reports a malformed [lyrics]/[ai] instead of
    // the feature being silently disabled.
    private struct StrictOptionalSections: Decodable {
        let ai: AIConfig?
        let lyrics: LyricsConfig?
    }

    func strictDecodeOptionalSections(content: String, path: String, configDir: String) throws {
        guard path.hasSuffix(".toml") else {
            _ = try JSONDecoder().decode(StrictOptionalSections.self, from: content.data(using: .utf8) ?? Data())
            return
        }
        _ = try TOMLDecoder().decode(StrictOptionalSections.self, from: preparedTomlTable(content: content, configDir: configDir))
    }

    func resolveIncludes(into table: TOMLTable, configDir: String) {
        guard let paths = table["includes"]?.array else { return }
        for element in paths {
            guard let relativePath = element.string else { continue }
            let file: File? =
                relativePath.hasPrefix("/")
                ? try? File(path: relativePath)
                : try? Folder(path: configDir).file(at: relativePath)
            guard let content = try? file?.readAsString(),
                let included = try? TOMLTable(string: content)
            else { continue }
            deepMerge(from: included, into: table)
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
