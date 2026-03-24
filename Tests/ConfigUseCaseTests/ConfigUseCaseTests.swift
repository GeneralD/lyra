import Dependencies
import Domain
import Foundation
import Testing
@testable import ConfigUseCase

@Suite("ConfigUseCase")
struct ConfigUseCaseTests {
    @Test("loadAppStyle delegates to repository")
    @MainActor
    func loadAppStyleDelegatesToRepository() {
        let customURL = URL(string: "https://example.com/wallpaper.mp4")!
        let expected = AppStyle(wallpaperURL: customURL)
        withDependencies {
            $0.configRepository = MockConfigRepository(style: expected)
        } operation: {
            let useCase = ConfigUseCaseImpl()
            let result = useCase.loadAppStyle()
            #expect(result.wallpaperURL == expected.wallpaperURL)
        }
    }

    @Test("loadAppStyle returns exact AppStyle from repository, not default")
    @MainActor
    func loadAppStyleReturnsRepositoryValue() {
        let customURL = URL(string: "https://example.com/custom.mp4")!
        let style = AppStyle(wallpaperURL: customURL)
        withDependencies {
            $0.configRepository = MockConfigRepository(style: style)
        } operation: {
            let useCase = ConfigUseCaseImpl()
            let result = useCase.loadAppStyle()
            let defaultStyle = AppStyle()
            #expect(result.wallpaperURL != defaultStyle.wallpaperURL)
            #expect(result.wallpaperURL == customURL)
        }
    }
}

// MARK: - Mocks

private struct MockConfigRepository: ConfigRepository {
    let style: AppStyle

    @MainActor
    func loadAppStyle() -> AppStyle { style }

    func validate() -> ConfigValidationResult { .defaults }
}
