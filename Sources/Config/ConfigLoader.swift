import Dependencies
import Domain
import Foundation
import TOMLKit

public struct ConfigLoader: Sendable {
    private init() {}
    public static let shared = ConfigLoader()
}

extension ConfigLoader: HealthCheckable {
    public var serviceName: String { "Config" }

    public func healthCheck() async -> HealthCheckResult {
        switch validate() {
        case .loaded(let path):
            return HealthCheckResult(status: .pass, detail: "loaded (\(path))")
        case .defaults:
            return HealthCheckResult(status: .pass, detail: "using defaults (no config file found)")
        case .unreadable(let path):
            return HealthCheckResult(status: .fail, detail: "cannot read \(path)")
        case .decodeError(let path, let error):
            return HealthCheckResult(status: .fail, detail: "decode error in \(path): \(error)")
        }
    }
}

public enum ConfigValidationResult {
    case loaded(path: String)
    case defaults
    case unreadable(path: String)
    case decodeError(path: String, error: String)
}

public extension ConfigLoader {
    func validate() -> ConfigValidationResult {
        let home = NSHomeDirectory()
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
        let candidates = [
            "\(xdgConfig)/lyra/config.toml",
            "\(home)/.lyra/config.toml",
            "\(xdgConfig)/lyra/config.json",
            "\(home)/.lyra/config.json",
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return .defaults
        }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .unreadable(path: path)
        }
        let configDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        do {
            try decodeOrThrow(content: content, path: path, configDir: configDir)
            return .loaded(path: path)
        } catch {
            return .decodeError(path: path, error: error.localizedDescription)
        }
    }

    func load() -> AppConfig {
        let home = NSHomeDirectory()
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
        let candidates = [
            "\(xdgConfig)/lyra/config.toml",
            "\(home)/.lyra/config.toml",
            "\(xdgConfig)/lyra/config.json",
            "\(home)/.lyra/config.json",
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let content = try? String(contentsOfFile: path, encoding: .utf8)
        else { return .defaults }

        let configDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard let decoded = decode(content: content, path: path, configDir: configDir) else { return .defaults }

        let wallpaper = decoded.wallpaper.map { resolveWallpaperPath($0, configDir: configDir) }
        return AppConfig(
            text: decoded.text, artwork: decoded.artwork, ripple: decoded.ripple,
            screen: decoded.screen, wallpaper: wallpaper,
            ai: decoded.ai
        )
    }
}

extension ConfigLoader {
    @discardableResult
    func decodeOrThrow(content: String, path: String, configDir: String) throws -> AppConfig {
        if path.hasSuffix(".toml") {
            let table = try TOMLTable(string: content)
            resolveIncludes(into: table, configDir: configDir)
            table.remove(at: "includes")
            return try TOMLDecoder().decode(AppConfig.self, from: table)
        } else {
            return try JSONDecoder().decode(AppConfig.self, from: content.data(using: .utf8) ?? Data())
        }
    }

    func decode(content: String, path: String, configDir: String) -> AppConfig? {
        if path.hasSuffix(".toml") {
            do {
                let table = try TOMLTable(string: content)
                resolveIncludes(into: table, configDir: configDir)
                table.remove(at: "includes")
                return try TOMLDecoder().decode(AppConfig.self, from: table)
            } catch {
                notifyError(path: path, error: error)
                return nil
            }
        } else {
            do {
                return try JSONDecoder().decode(AppConfig.self, from: content.data(using: .utf8) ?? Data())
            } catch {
                notifyError(path: path, error: error)
                return nil
            }
        }
    }

    func resolveIncludes(into table: TOMLTable, configDir: String) {
        guard let paths = table["includes"]?.array else { return }
        for element in paths {
            guard let relativePath = element.string else { continue }
            let absolutePath = relativePath.hasPrefix("/")
                ? relativePath
                : URL(fileURLWithPath: configDir).appendingPathComponent(relativePath).path
            guard let content = try? String(contentsOfFile: absolutePath, encoding: .utf8),
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

    func resolveWallpaperPath(_ wallpaper: String, configDir: String) -> String {
        guard !wallpaper.hasPrefix("/") else { return wallpaper }
        return URL(fileURLWithPath: configDir).appendingPathComponent(wallpaper).path
    }

    func notifyError(path: String, error: Error) {
        fputs("lyra: failed to decode \(path): \(error)\n", stderr)
        @Dependency(\.userNotifier) var notifier
        notifier.notify(
            title: "lyra",
            subtitle: "Config error: \(URL(fileURLWithPath: path).lastPathComponent)",
            message: String(describing: error),
            fileToOpen: path
        )
    }
}
