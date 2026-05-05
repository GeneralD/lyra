import CryptoKit
import Files
import Foundation

struct WallpaperCache {
    let folder: Folder

    /// - Parameter cachePath: Override the cache root used for lookups.
    ///   Tests inject a temp directory directly to avoid `setenv` racing across
    ///   parallel suites (Swift Testing runs suites concurrently and process
    ///   environment is global). When `nil`, reads `XDG_CACHE_HOME` from the
    ///   process environment, falling back to `~/.cache`.
    init(cachePath: String? = nil) throws {
        let resolvedCachePath = cachePath ?? Self.cachePathFromEnvironment()
        let wallpaperPath = "\(resolvedCachePath)/lyra/wallpapers"
        try FileManager.default.createDirectory(atPath: wallpaperPath, withIntermediateDirectories: true)
        folder = try Folder(path: wallpaperPath)
    }

    private static func cachePathFromEnvironment() -> String {
        ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(Folder.home.path).cache"
    }

    func tempPath(for url: URL, ext: String? = nil) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = hash.map { String(format: "%02x", $0) }.joined()
        let resolvedExt = ext ?? (url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
        return folder.path + "\(hex).\(resolvedExt)"
    }
}
