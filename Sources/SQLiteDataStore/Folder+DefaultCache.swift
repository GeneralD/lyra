import Files
import Foundation

extension Folder {
    static var defaultCache: Folder {
        get throws {
            let envCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cachePath = (envCache?.isEmpty == false) ? envCache! : "\(Folder.home.path).cache"
            return try .init(path: cachePath)
        }
    }
}
