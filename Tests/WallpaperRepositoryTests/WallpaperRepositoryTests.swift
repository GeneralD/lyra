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
