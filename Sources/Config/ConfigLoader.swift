import Dependencies
import Foundation
import TOMLKit

// MARK: - Include resolution

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

private func deepMerge(from source: TOMLTable, into target: TOMLTable) {
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

// MARK: - Config error notification

func notifyConfigError(path: String, error: Error) {
    fputs("lyra: failed to decode \(path): \(error)\n", stderr)
    @Dependency(\.userNotifier) var notifier
    notifier.notify(
        title: "lyra",
        subtitle: "Config error: \((path as NSString).lastPathComponent)",
        message: String(describing: error),
        fileToOpen: path
    )
}
