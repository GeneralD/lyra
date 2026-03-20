import Dependencies
import Foundation
import TOMLKit

public struct ConfigLoader: Sendable {
    private init() {}
    public static let shared = ConfigLoader()
}

public extension ConfigLoader {
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

        let configDir = (path as NSString).deletingLastPathComponent
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
                : (configDir as NSString).appendingPathComponent(relativePath)
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
        return (configDir as NSString).appendingPathComponent(wallpaper)
    }

    func notifyError(path: String, error: Error) {
        fputs("lyra: failed to decode \(path): \(error)\n", stderr)
        @Dependency(\.userNotifier) var notifier
        notifier.notify(
            title: "lyra",
            subtitle: "Config error: \((path as NSString).lastPathComponent)",
            message: String(describing: error),
            fileToOpen: path
        )
    }
}
