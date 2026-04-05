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

    @Test("template delegates to repository")
    func templateDelegates() {
        withDependencies {
            $0.configRepository = MockConfigRepository(
                style: .init(), templateResult: "# config template")
        } operation: {
            let useCase = ConfigUseCaseImpl()
            #expect(useCase.template(format: .toml) == "# config template")
        }
    }

    @Test("writeTemplate delegates to repository")
    func writeTemplateDelegates() throws {
        try withDependencies {
            $0.configRepository = MockConfigRepository(
                style: .init(), writeTemplateResult: "/path/to/config.toml")
        } operation: {
            let useCase = ConfigUseCaseImpl()
            let path = try useCase.writeTemplate(format: .toml, force: false)
            #expect(path == "/path/to/config.toml")
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
    var style: AppStyle = .init()
    var templateResult: String?
    var writeTemplateResult: String = ""

    func loadAppStyle() -> AppStyle { style }

    func validate() -> ConfigValidationResult { .defaults }
    func template(format: ConfigFormat) -> String? { templateResult }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { writeTemplateResult }
    var existingConfigPath: String? { nil }
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
    var existingConfigPath: String? { nil }
}
