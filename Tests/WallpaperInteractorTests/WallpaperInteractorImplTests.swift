import Dependencies
import Domain
import Foundation
import Testing

@testable import WallpaperInteractor

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var style: AppStyle = .init()
    var appStyle: AppStyle { style }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

private struct StubWallpaperUseCase: WallpaperUseCase, Sendable {
    var result: URL?

    func resolveWallpaper(value: String?, configDir: String) async throws -> URL? {
        result
    }
}

@Suite("WallpaperInteractor")
struct WallpaperInteractorImplTests {

    @Test("resolveWallpaper returns empty state when no wallpaper configured")
    func noWallpaperConfig() async throws {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
            $0.wallpaperUseCase = StubWallpaperUseCase()
        } operation: {
            WallpaperInteractorImpl()
        }

        let state = try await interactor.resolveWallpaper()
        #expect(state.url == nil)
        #expect(state.start == nil)
        #expect(state.end == nil)
    }

    @Test("rippleConfig returns config from appStyle")
    func rippleConfigFromAppStyle() {
        let style = AppStyle(ripple: RippleStyle(enabled: true, idle: 3.0))
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
            $0.wallpaperUseCase = StubWallpaperUseCase()
        } operation: {
            WallpaperInteractorImpl()
        }

        #expect(interactor.rippleConfig.enabled == true)
        #expect(interactor.rippleConfig.idle == 3.0)
    }
}
