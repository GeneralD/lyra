import Foundation
import Testing

@testable import WallpaperDataSource

@Suite("WallpaperCache", .serialized)
struct WallpaperCacheTests {
    private func withTempCacheDir<T>(_ body: (String) throws -> T) throws -> T {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        setenv("XDG_CACHE_HOME", tmp, 1)
        defer {
            unsetenv("XDG_CACHE_HOME")
            try? FileManager.default.removeItem(atPath: tmp)
        }
        return try body(tmp)
    }

    @Test("same URL produces same temp path")
    func sameURLProducesSameTempPath() throws {
        try withTempCacheDir { _ in
            let cache = try WallpaperCache()
            let url = URL(string: "https://example.com/video.mp4")!
            #expect(cache.tempPath(for: url) == cache.tempPath(for: url))
        }
    }

    @Test("different URLs produce different temp paths")
    func differentURLsProduceDifferentTempPaths() throws {
        try withTempCacheDir { _ in
            let cache = try WallpaperCache()
            let url1 = URL(string: "https://example.com/a.mp4")!
            let url2 = URL(string: "https://example.com/b.mp4")!
            #expect(cache.tempPath(for: url1) != cache.tempPath(for: url2))
        }
    }

    @Test("default extension is mp4 when URL has no extension")
    func defaultExtensionIsMp4() throws {
        try withTempCacheDir { _ in
            let cache = try WallpaperCache()
            let url = URL(string: "https://example.com/noext")!
            #expect(cache.tempPath(for: url).hasSuffix(".mp4"))
        }
    }

    @Test("preserves URL path extension when present")
    func preservesURLPathExtension() throws {
        try withTempCacheDir { _ in
            let cache = try WallpaperCache()
            let url = URL(string: "https://example.com/video.mov")!
            #expect(cache.tempPath(for: url).hasSuffix(".mov"))
        }
    }

    @Test("custom ext parameter overrides URL extension")
    func customExtOverridesURLExtension() throws {
        try withTempCacheDir { _ in
            let cache = try WallpaperCache()
            let url = URL(string: "https://example.com/video.mov")!
            #expect(cache.tempPath(for: url, ext: "webm").hasSuffix(".webm"))
        }
    }

    @Test("file name matches pattern: 64 hex chars + dot + extension")
    func fileNameMatchesHexPattern() throws {
        try withTempCacheDir { _ in
            let cache = try WallpaperCache()
            let urls = [
                URL(string: "https://example.com/a.mp4")!,
                URL(string: "https://example.com/b")!,
                URL(string: "https://example.com/c.mov")!,
            ]
            let hexPattern = #/^[0-9a-f]{64}\.\w+$/#
            for url in urls {
                let fileName = URL(fileURLWithPath: cache.tempPath(for: url)).lastPathComponent
                #expect(fileName.wholeMatch(of: hexPattern) != nil, "Expected hex pattern, got: \(fileName)")
            }
        }
    }

    @Test("SHA256 is deterministic: same URL always produces same hash")
    func sha256IsDeterministic() throws {
        try withTempCacheDir { _ in
            let cache1 = try WallpaperCache()
            let cache2 = try WallpaperCache()
            let url = URL(string: "https://example.com/deterministic.mp4")!
            #expect(cache1.tempPath(for: url) == cache2.tempPath(for: url))
        }
    }
}
