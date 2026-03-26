import Dependencies
import Domain
import Foundation
import Testing

@testable import ConfigUseCase

@Suite("ConfigUseCase")
struct ConfigUseCaseTests {
    @Test("appStyle delegates to repository")
    func appStyleDelegatesToRepository() {
        let expected = AppStyle(wallpaper: WallpaperStyle(location: "bg.mp4"), configDir: "/tmp")
        withDependencies {
            $0.configRepository = MockConfigRepository(style: expected)
        } operation: {
            let useCase = ConfigUseCaseImpl()
            let result = useCase.appStyle
            #expect(result.wallpaper?.location == expected.wallpaper?.location)
            #expect(result.configDir == expected.configDir)
        }
    }

    @Test("appStyle returns exact AppStyle from repository, not default")
    func appStyleReturnsRepositoryValue() {
        let style = AppStyle(wallpaper: WallpaperStyle(location: "custom.mp4"), configDir: "/custom")
        withDependencies {
            $0.configRepository = MockConfigRepository(style: style)
        } operation: {
            let useCase = ConfigUseCaseImpl()
            let result = useCase.appStyle
            let defaultStyle = AppStyle()
            #expect(result.wallpaper?.location != defaultStyle.wallpaper?.location)
            #expect(result.wallpaper?.location == "custom.mp4")
        }
    }

    @Test("appStyle is cached — repository.loadAppStyle() called only once")
    func appStyleCachedSingleRead() {
        let counter = CountingConfigRepository()
        withDependencies {
            $0.configRepository = counter
        } operation: {
            let useCase = ConfigUseCaseImpl()
            _ = useCase.appStyle
            _ = useCase.appStyle
            _ = useCase.appStyle
            #expect(counter.callCount == 1)
        }
    }
}

// MARK: - Mocks

private struct MockConfigRepository: ConfigRepository {
    let style: AppStyle

    func loadAppStyle() -> AppStyle { style }

    func validate() -> ConfigValidationResult { .defaults }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
}

private final class CountingConfigRepository: ConfigRepository, @unchecked Sendable {
    var callCount = 0

    func loadAppStyle() -> AppStyle {
        callCount += 1
        return .init()
    }

    func validate() -> ConfigValidationResult { .defaults }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
}
