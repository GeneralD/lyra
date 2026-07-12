import Dependencies
import Domain
import Foundation
import Testing

@testable import WallpaperRepository

// MARK: - Stub DataSources

private final class SpyLocalDataSource: WallpaperDataSource, @unchecked Sendable {
    private(set) var calledWith: LocalWallpaper?
    var result: String = "/resolved/local/path.mp4"
    var error: (any Error)?

    func resolve(_ location: LocalWallpaper) async throws -> String {
        calledWith = location
        if let error { throw error }
        return result
    }
}

private final class SpyRemoteDataSource: WallpaperDataSource, @unchecked Sendable {
    private(set) var calledWith: RemoteWallpaper?
    var result: String = "/resolved/remote/path.mp4"
    var error: (any Error)?

    func resolve(_ location: RemoteWallpaper) async throws -> String {
        calledWith = location
        if let error { throw error }
        return result
    }
}

private final class SpyYouTubeDataSource: WallpaperDataSource, @unchecked Sendable {
    private(set) var calledWith: YouTubeWallpaper?
    var result: String = "/resolved/youtube/path.mp4"
    var error: (any Error)?

    func resolve(_ location: YouTubeWallpaper) async throws -> String {
        calledWith = location
        if let error { throw error }
        return result
    }
}

private enum StubError: Error {
    case dataSourceFailed
}

private final class StubCacheStore: WallpaperCacheStore, @unchecked Sendable {
    let entry: WallpaperCacheEntry?

    init(entry: WallpaperCacheEntry? = nil) {
        self.entry = entry
    }

    func read(url: String) async -> WallpaperCacheEntry? { entry }
    func write(url: String, contentHash: String, fileExt: String) async throws {}
}

// MARK: - Tests

@Suite("WallpaperRepository")
struct WallpaperRepositoryTests {

    // MARK: - Normal Behavior

    @Suite("Normal Behavior")
    struct NormalBehavior {

        @Test("nil value returns nil")
        func nilValueReturnsNil() async throws {
            try await withDependencies {
                $0.localWallpaperDataSource = SpyLocalDataSource()
                $0.remoteWallpaperDataSource = SpyRemoteDataSource()
                $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            } operation: {
                let repo = WallpaperRepositoryImpl()
                let result = try await repo.resolve(value: nil, configDir: "/tmp")
                #expect(result == nil)
            }
        }

        @Test("empty string returns nil")
        func emptyStringReturnsNil() async throws {
            try await withDependencies {
                $0.localWallpaperDataSource = SpyLocalDataSource()
                $0.remoteWallpaperDataSource = SpyRemoteDataSource()
                $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            } operation: {
                let repo = WallpaperRepositoryImpl()
                let result = try await repo.resolve(value: "", configDir: "/tmp")
                #expect(result == nil)
            }
        }

        @Test("local path dispatches to local DataSource")
        func localPathDispatchesToLocal() async throws {
            let local = SpyLocalDataSource()
            let remote = SpyRemoteDataSource()
            let youtube = SpyYouTubeDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = local
                $0.remoteWallpaperDataSource = remote
                $0.youtubeWallpaperDataSource = youtube
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(value: "/Users/me/bg.mp4", configDir: "/config")

                #expect(local.calledWith != nil)
                #expect(local.calledWith?.path == "/Users/me/bg.mp4")
                #expect(local.calledWith?.configDir == "/config")
                #expect(remote.calledWith == nil)
                #expect(youtube.calledWith == nil)
            }
        }

        @Test("HTTP URL dispatches to remote DataSource")
        func httpUrlDispatchesToRemote() async throws {
            let local = SpyLocalDataSource()
            let remote = SpyRemoteDataSource()
            let youtube = SpyYouTubeDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = local
                $0.remoteWallpaperDataSource = remote
                $0.youtubeWallpaperDataSource = youtube
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(value: "http://example.com/bg.mp4", configDir: "/tmp")

                #expect(local.calledWith == nil)
                #expect(remote.calledWith != nil)
                #expect(remote.calledWith?.url.absoluteString == "http://example.com/bg.mp4")
                #expect(youtube.calledWith == nil)
            }
        }

        @Test("HTTPS URL dispatches to remote DataSource")
        func httpsUrlDispatchesToRemote() async throws {
            let local = SpyLocalDataSource()
            let remote = SpyRemoteDataSource()
            let youtube = SpyYouTubeDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = local
                $0.remoteWallpaperDataSource = remote
                $0.youtubeWallpaperDataSource = youtube
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(value: "https://example.com/bg.mp4", configDir: "/tmp")

                #expect(local.calledWith == nil)
                #expect(remote.calledWith != nil)
                #expect(youtube.calledWith == nil)
            }
        }

        @Test("YouTube URL (youtube.com) dispatches to youtube DataSource")
        func youtubeComDispatches() async throws {
            let local = SpyLocalDataSource()
            let remote = SpyRemoteDataSource()
            let youtube = SpyYouTubeDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = local
                $0.remoteWallpaperDataSource = remote
                $0.youtubeWallpaperDataSource = youtube
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(
                    value: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", configDir: "/tmp")

                #expect(local.calledWith == nil)
                #expect(remote.calledWith == nil)
                #expect(youtube.calledWith != nil)
            }
        }

        @Test("YouTube short URL (youtu.be) dispatches to youtube DataSource")
        func youtuBeDispatches() async throws {
            let local = SpyLocalDataSource()
            let remote = SpyRemoteDataSource()
            let youtube = SpyYouTubeDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = local
                $0.remoteWallpaperDataSource = remote
                $0.youtubeWallpaperDataSource = youtube
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(value: "https://youtu.be/dQw4w9WgXcQ", configDir: "/tmp")

                #expect(local.calledWith == nil)
                #expect(remote.calledWith == nil)
                #expect(youtube.calledWith != nil)
            }
        }
    }

    // MARK: - Boundary Conditions

    @Suite("Boundary Conditions")
    struct BoundaryConditions {

        @Test("whitespace-only value dispatches to local DataSource as-is")
        func whitespaceOnlyGoesToLocal() async throws {
            let local = SpyLocalDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = local
                $0.remoteWallpaperDataSource = SpyRemoteDataSource()
                $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(value: "   ", configDir: "/tmp")

                #expect(local.calledWith != nil)
                #expect(local.calledWith?.path == "   ")
            }
        }

        @Test("URL with uppercase scheme (HTTPS://) dispatches to remote")
        func uppercaseSchemeDispatches() async throws {
            let remote = SpyRemoteDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = SpyLocalDataSource()
                $0.remoteWallpaperDataSource = remote
                $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(value: "HTTPS://example.com/bg.mp4", configDir: "/tmp")

                #expect(remote.calledWith != nil)
            }
        }

        @Test("YouTube URL with extra query params dispatches to youtube")
        func youtubeWithQueryParams() async throws {
            let youtube = SpyYouTubeDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = SpyLocalDataSource()
                $0.remoteWallpaperDataSource = SpyRemoteDataSource()
                $0.youtubeWallpaperDataSource = youtube
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(
                    value: "https://www.youtube.com/watch?v=abc123&t=1s&list=PLxyz",
                    configDir: "/tmp")

                #expect(youtube.calledWith != nil)
                #expect(youtube.calledWith?.url.absoluteString.contains("t=1s") == true)
            }
        }

        @Test("YouTube URL without www. prefix dispatches to youtube")
        func youtubeWithoutWww() async throws {
            let youtube = SpyYouTubeDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = SpyLocalDataSource()
                $0.remoteWallpaperDataSource = SpyRemoteDataSource()
                $0.youtubeWallpaperDataSource = youtube
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(
                    value: "https://youtube.com/watch?v=abc123", configDir: "/tmp")

                #expect(youtube.calledWith != nil)
            }
        }

        @Test("URL with no path extension dispatches to remote")
        func urlNoPathExtension() async throws {
            let remote = SpyRemoteDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = SpyLocalDataSource()
                $0.remoteWallpaperDataSource = remote
                $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(value: "https://example.com/video", configDir: "/tmp")

                #expect(remote.calledWith != nil)
            }
        }

        @Test("URL with fragment dispatches to remote")
        func urlWithFragment() async throws {
            let remote = SpyRemoteDataSource()

            try await withDependencies {
                $0.localWallpaperDataSource = SpyLocalDataSource()
                $0.remoteWallpaperDataSource = remote
                $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            } operation: {
                let repo = WallpaperRepositoryImpl()
                _ = try await repo.resolve(
                    value: "https://example.com/bg.mp4#t=10", configDir: "/tmp")

                #expect(remote.calledWith != nil)
                #expect(remote.calledWith?.url.absoluteString.contains("#t=10") == true)
            }
        }
    }

    // MARK: - Error Handling

    @Suite("Error Handling")
    struct ErrorHandling {

        @Test("DataSource throws error propagates")
        func dataSourceErrorPropagates() async {
            let local = SpyLocalDataSource()
            local.error = StubError.dataSourceFailed

            await withDependencies {
                $0.localWallpaperDataSource = local
                $0.remoteWallpaperDataSource = SpyRemoteDataSource()
                $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            } operation: {
                let repo = WallpaperRepositoryImpl()
                await #expect(throws: StubError.self) {
                    try await repo.resolve(value: "/some/path.mp4", configDir: "/tmp")
                }
            }
        }

        @Test("result URL always has file scheme")
        func resultUrlHasFileScheme() async throws {
            try await withDependencies {
                $0.localWallpaperDataSource = SpyLocalDataSource()
                $0.remoteWallpaperDataSource = SpyRemoteDataSource()
                $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            } operation: {
                let repo = WallpaperRepositoryImpl()

                let localResult = try await repo.resolve(value: "/some/path.mp4", configDir: "/tmp")
                #expect(localResult?.scheme == "file")

                let remoteResult = try await repo.resolve(
                    value: "https://example.com/bg.mp4", configDir: "/tmp")
                #expect(remoteResult?.scheme == "file")

                let youtubeResult = try await repo.resolve(
                    value: "https://youtube.com/watch?v=abc", configDir: "/tmp")
                #expect(youtubeResult?.scheme == "file")
            }
        }
    }

    // MARK: - Properties

    @Suite("Properties")
    struct Properties {

        @Test("same input always produces same output (deterministic)")
        func deterministic() async throws {
            let local = SpyLocalDataSource()
            local.result = "/stable/path.mp4"

            try await withDependencies {
                $0.localWallpaperDataSource = local
                $0.remoteWallpaperDataSource = SpyRemoteDataSource()
                $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            } operation: {
                let repo = WallpaperRepositoryImpl()
                let first = try await repo.resolve(value: "bg.mp4", configDir: "/config")
                let second = try await repo.resolve(value: "bg.mp4", configDir: "/config")
                #expect(first == second)
            }
        }
    }
}

// Exercises the download → SHA256 → cache-dedup path against an injected cache
// root (cacheHome), so no real ~/.cache write happens.
@Suite("WallpaperRepository cache & hashing")
struct WallpaperRepositoryCacheTests {
    private func makeTempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "lyra-wp-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("hashes and caches a downloaded file into the injected cache root")
    func hashesDownloadedFileIntoInjectedCacheRoot() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // A real, non-empty download so streamingSHA256's read loop runs.
        let sourceFile = tempDir + "/download.mp4"
        try Data(repeating: 0xAB, count: 4096).write(to: URL(fileURLWithPath: sourceFile))

        let remote = SpyRemoteDataSource()
        remote.result = sourceFile

        let result = try await withDependencies {
            $0.localWallpaperDataSource = SpyLocalDataSource()
            $0.remoteWallpaperDataSource = remote
            $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            $0.wallpaperCacheStore = StubCacheStore()
        } operation: {
            let repo = WallpaperRepositoryImpl(cacheHome: tempDir)
            return try await repo.resolve(value: "https://example.com/bg.mp4", configDir: "/tmp")
        }

        let path = try #require(result?.path)
        #expect(path.hasPrefix(tempDir + "/lyra/wallpapers/"))
        #expect(path.hasSuffix(".mp4"))
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(!FileManager.default.fileExists(atPath: sourceFile))  // moved into cache
    }

    @Test("returns the cached file when the store has an entry and the file exists")
    func returnsCachedFileOnHit() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Pre-seed the exact cache file the store's entry points to.
        let wallpapersDir = tempDir + "/lyra/wallpapers"
        try FileManager.default.createDirectory(atPath: wallpapersDir, withIntermediateDirectories: true)
        let cachedFile = "\(wallpapersDir)/deadbeef.mp4"
        try Data("cached".utf8).write(to: URL(fileURLWithPath: cachedFile))

        let remote = SpyRemoteDataSource()

        let result = try await withDependencies {
            $0.localWallpaperDataSource = SpyLocalDataSource()
            $0.remoteWallpaperDataSource = remote
            $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            $0.wallpaperCacheStore = StubCacheStore(entry: .init(contentHash: "deadbeef", fileExt: "mp4"))
        } operation: {
            let repo = WallpaperRepositoryImpl(cacheHome: tempDir)
            return try await repo.resolve(value: "https://example.com/bg.mp4", configDir: "/tmp")
        }

        #expect(result?.path == cachedFile)
        #expect(remote.calledWith == nil)  // cache hit short-circuits before download
    }

    @Test("removes the temp download when an identical file is already cached")
    func removesTempWhenAlreadyCached() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Two temp files with identical content hash to the same cache path.
        let content = Data(repeating: 0xCD, count: 2048)
        let first = tempDir + "/first.mp4"
        let second = tempDir + "/second.mp4"
        try content.write(to: URL(fileURLWithPath: first))
        try content.write(to: URL(fileURLWithPath: second))

        let remote = SpyRemoteDataSource()

        try await withDependencies {
            $0.localWallpaperDataSource = SpyLocalDataSource()
            $0.remoteWallpaperDataSource = remote
            $0.youtubeWallpaperDataSource = SpyYouTubeDataSource()
            $0.wallpaperCacheStore = StubCacheStore()  // never a cache hit → always downloads
        } operation: {
            let repo = WallpaperRepositoryImpl(cacheHome: tempDir)
            remote.result = first
            _ = try await repo.resolve(value: "https://example.com/first.mp4", configDir: "/tmp")
            remote.result = second
            _ = try await repo.resolve(value: "https://example.com/second.mp4", configDir: "/tmp")
        }

        // First was moved into cache; the identical second was discarded, not moved.
        #expect(!FileManager.default.fileExists(atPath: first))
        #expect(!FileManager.default.fileExists(atPath: second))
    }
}
