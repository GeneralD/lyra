import Domain
import Files
import Foundation
import TOMLKit

public struct ConfigDataSourceImpl: Sendable {
    public init() {}
}

extension ConfigDataSourceImpl: ConfigDataSource {
    public func load() -> ConfigLoadResult? {
        guard let file = findConfigFile(),
            let content = try? file.readAsString()
        else { return nil }
        let configDir = file.parent?.path ?? Folder.home.path
        guard let config = decode(content: content, path: file.path, configDir: configDir) else { return nil }
        return ConfigLoadResult(config: config, configDir: configDir, path: file.path)
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

    public func tryDecode() throws -> String {
        guard let file = findConfigFile(),
            let content = try? file.readAsString()
        else { return "" }
        let configDir = file.parent?.path ?? Folder.home.path
        try decodeOrThrow(content: content, path: file.path, configDir: configDir)
        return file.path
    }
}

extension ConfigDataSourceImpl {
    func findConfigFile() -> File? {
        let home = Folder.home
        let xdgConfigFolder: Folder? = {
            let envXdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard let path = envXdg, !path.isEmpty else {
                return try? home.subfolder(named: ".config")
            }
            return try? Folder(path: path)
        }()
        let lyraXdg = try? xdgConfigFolder?.subfolder(named: "lyra")
        let lyraDot = try? home.subfolder(named: ".lyra")
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

    func lyraConfigFolder() throws -> Folder {
        let home = Folder.home
        let envXdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let xdgConfigPath =
            (envXdg?.isEmpty == false) ? envXdg! : "\(home.path).config"
        let lyraPath = "\(xdgConfigPath)/lyra"
        try FileManager.default.createDirectory(atPath: lyraPath, withIntermediateDirectories: true)
        return try Folder(path: lyraPath)
    }

    @discardableResult
    func decodeOrThrow(content: String, path: String, configDir: String) throws -> AppConfig {
        guard path.hasSuffix(".toml") else {
            return try JSONDecoder().decode(AppConfig.self, from: content.data(using: .utf8) ?? Data())
        }
        let table = try TOMLTable(string: content)
        resolveIncludes(into: table, configDir: configDir)
        table.remove(at: "includes")
        return try TOMLDecoder().decode(AppConfig.self, from: table)
    }

    func decode(content: String, path: String, configDir: String) -> AppConfig? {
        try? decodeOrThrow(content: content, path: path, configDir: configDir)
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
