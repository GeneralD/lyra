import Dependencies
import Domain
import Foundation
import Testing

@testable import WallpaperUseCase

private struct StubWallpaperRepository: WallpaperRepository, Sendable {
    var result: URL?

    func resolve(value: String?, configDir: String) async throws -> URL? {
        result
    }
}

@Suite("WallpaperUseCase")
struct WallpaperUseCaseImplTests {

    @Test("resolveWallpaper delegates to repository")
    func delegatesToRepository() async throws {
        let expectedURL = URL(fileURLWithPath: "/tmp/video.mp4")
        let useCase = withDependencies {
            $0.wallpaperRepository = StubWallpaperRepository(result: expectedURL)
        } operation: {
            WallpaperUseCaseImpl()
        }

        let result = try await useCase.resolveWallpaper(value: "video.mp4", configDir: "/config")
        #expect(result == expectedURL)
    }

    @Test("resolveWallpaper returns nil when repository returns nil")
    func returnsNil() async throws {
        let useCase = withDependencies {
            $0.wallpaperRepository = StubWallpaperRepository(result: nil)
        } operation: {
            WallpaperUseCaseImpl()
        }

        let result = try await useCase.resolveWallpaper(value: nil, configDir: "/config")
        #expect(result == nil)
    }
}
