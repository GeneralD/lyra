import CryptoKit
import Dependencies
import Domain
import Foundation

public struct WallpaperRepositoryImpl: Sendable {
    @Dependency(\.localWallpaperDataSource) private var local
    @Dependency(\.remoteWallpaperDataSource) private var remote
    @Dependency(\.youtubeWallpaperDataSource) private var youtube
    @Dependency(\.wallpaperCacheStore) private var cacheStore

    public init() {}
}

extension WallpaperRepositoryImpl: WallpaperRepository {
    public func resolve(value: String?, configDir: String) async throws -> URL? {
        guard let value, !value.isEmpty else { return nil }
        let path = try await resolveToPath(value: value, configDir: configDir)
        return URL(fileURLWithPath: path)
    }
}

extension WallpaperRepositoryImpl {
    private func resolveToPath(value: String, configDir: String) async throws -> String {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            // Local files don't need cache deduplication
            return try await local.resolve(LocalWallpaper(path: value, configDir: configDir))
        }

        // Check DB cache first
        if let entry = await cacheStore.read(url: value) {
            let cacheDir = try Self.wallpaperCacheDir()
            let cachedPath = "\(cacheDir)/\(entry.contentHash).\(entry.fileExt)"
            if FileManager.default.fileExists(atPath: cachedPath) {
                return cachedPath
            }
        }

        // Download via appropriate DataSource (returns temp file path)
        let tempPath =
            url.isYouTube
            ? try await youtube.resolve(YouTubeWallpaper(url: url))
            : try await remote.resolve(RemoteWallpaper(url: url))

        // Compute content hash and deduplicate
        return try await deduplicateAndCache(tempPath: tempPath, url: value)
    }

    private func deduplicateAndCache(tempPath: String, url: String) async throws -> String {
        let ext = (tempPath as NSString).pathExtension.isEmpty ? "mp4" : (tempPath as NSString).pathExtension
        let contentHash = try Self.streamingSHA256(of: tempPath)
        let cacheDir = try Self.wallpaperCacheDir()
        let finalPath = "\(cacheDir)/\(contentHash).\(ext)"

        // Move temp file to content-hash-based path (skip if already exists from another URL)
        if !FileManager.default.fileExists(atPath: finalPath) {
            try? FileManager.default.moveItem(
                at: URL(fileURLWithPath: tempPath),
                to: URL(fileURLWithPath: finalPath))
        } else {
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        // Record URL → content-hash mapping
        try? await cacheStore.write(url: url, contentHash: contentHash, fileExt: ext)

        return finalPath
    }

    private static func streamingSHA256(of path: String) throws -> String {
        guard let stream = InputStream(fileAtPath: path) else {
            throw NSError(domain: "WallpaperRepository", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read file"])
        }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            guard bytesRead > 0 else { break }
            hasher.update(data: buffer[..<bytesRead])
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func wallpaperCacheDir() throws -> String {
        let envCache =
            ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(NSHomeDirectory())/.cache"
        let wallpaperPath = "\(envCache)/lyra/wallpapers"
        try FileManager.default.createDirectory(atPath: wallpaperPath, withIntermediateDirectories: true)
        return wallpaperPath
    }
}
