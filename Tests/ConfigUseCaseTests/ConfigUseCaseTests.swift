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
            #expect(result.wallpaper?.items.first?.location == expected.wallpaper?.items.first?.location)
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
            #expect(result.wallpaper?.items.first?.location != defaultStyle.wallpaper?.items.first?.location)
            #expect(result.wallpaper?.items.first?.location == "custom.mp4")
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

    @Test("appStyle は初回に一度ロードされキャッシュされる")
    func appStyleLoadsOnceThenCaches() {
        let counter = CountingConfigRepository()
        withDependencies {
            $0.configRepository = counter
        } operation: {
            let useCase = ConfigUseCaseImpl()
            _ = useCase.appStyle
            _ = useCase.appStyle
            #expect(counter.callCount == 1)
        }
    }

    @Test("reload はディスクを再読込し .updated を返す")
    func reloadUpdatesFromDisk() {
        let counter = CountingConfigRepository()
        counter.validation = .loaded(path: "/c.toml")
        withDependencies {
            $0.configRepository = counter
        } operation: {
            let useCase = ConfigUseCaseImpl()
            _ = useCase.appStyle  // Initial load (count 1).
            let outcome = useCase.reload()  // Reload from disk (count 2).
            #expect(counter.callCount == 2)
            guard case .updated = outcome else {
                Issue.record("expected .updated")
                return
            }
            // The store now holds the freshly loaded style, not the cached one.
            #expect(useCase.appStyle.wallpaper?.items.first?.location == "reloaded.mp4")
        }
    }

    @Test("decodeError では前回値を保持し .invalid を返す")
    func reloadKeepsPreviousOnDecodeError() {
        let counter = CountingConfigRepository()
        counter.validation = .decodeError(path: "/c.toml", error: "syntax")
        withDependencies {
            $0.configRepository = counter
        } operation: {
            let useCase = ConfigUseCaseImpl()
            _ = useCase.appStyle  // count 1
            let outcome = useCase.reload()  // Validation fails; loadAppStyle is not called (count remains 1).
            #expect(counter.callCount == 1)
            guard case .invalid(let f) = outcome else {
                Issue.record("expected .invalid")
                return
            }
            #expect(f.reason == .decode("syntax"))
            // The store still holds the last-good style — never reset on a bad edit.
            #expect(useCase.appStyle.wallpaper?.items.first?.location == "initial.mp4")
        }
    }

    @Test("ファイル存在下の .defaults は読取失敗とみなし前回値保持")
    func reloadTreatsDefaultsWithExistingFileAsUnreadable() {
        let counter = CountingConfigRepository()
        counter.validation = .defaults
        counter.pathExists = true
        withDependencies {
            $0.configRepository = counter
        } operation: {
            let useCase = ConfigUseCaseImpl()
            _ = useCase.appStyle
            let outcome = useCase.reload()
            guard case .invalid(let f) = outcome else {
                Issue.record("expected .invalid")
                return
            }
            #expect(f.reason == .unreadable)
            // The store still holds the last-good style — never reset on a bad edit.
            #expect(useCase.appStyle.wallpaper?.items.first?.location == "initial.mp4")
        }
    }

    @Test("validate の .unreadable は .invalid(.unreadable) として前回値保持")
    func reloadSurfacesUnreadableValidation() {
        let counter = CountingConfigRepository()
        counter.validation = .unreadable(path: "/c.toml")
        withDependencies {
            $0.configRepository = counter
        } operation: {
            let useCase = ConfigUseCaseImpl()
            _ = useCase.appStyle
            let outcome = useCase.reload()  // Validation fails; loadAppStyle is not called (count remains 1).
            #expect(counter.callCount == 1)
            guard case .invalid(let f) = outcome else {
                Issue.record("expected .invalid")
                return
            }
            #expect(f.path == "/c.toml")
            #expect(f.reason == .unreadable)
            // The store still holds the last-good style — never reset on a bad edit.
            #expect(useCase.appStyle.wallpaper?.items.first?.location == "initial.mp4")
        }
    }

    @Test("ファイル不在の .defaults は正当なデフォルト適用として .updated")
    func reloadAppliesDefaultsWhenNoFile() {
        let counter = CountingConfigRepository()
        counter.validation = .defaults
        counter.pathExists = false
        withDependencies {
            $0.configRepository = counter
        } operation: {
            let useCase = ConfigUseCaseImpl()
            _ = useCase.appStyle
            let outcome = useCase.reload()
            guard case .updated = outcome else {
                Issue.record("expected .updated")
                return
            }
            // A deliberate removal replaces the store with the freshly loaded
            // (defaults) style instead of clinging to the previous one.
            #expect(useCase.appStyle.wallpaper?.items.first?.location == "reloaded.mp4")
        }
    }
}

@Test("existingConfigPath delegates to repository")
func existingConfigPathDelegates() {
    withDependencies {
        $0.configRepository = MockConfigRepository(
            style: .init(), configPath: "/home/user/.config/lyra/config.toml")
    } operation: {
        let useCase = ConfigUseCaseImpl()
        #expect(useCase.existingConfigPath == "/home/user/.config/lyra/config.toml")
    }
}

@Test("existingConfigPath returns nil when no config exists")
func existingConfigPathNil() {
    withDependencies {
        $0.configRepository = MockConfigRepository(style: .init(), configPath: nil)
    } operation: {
        let useCase = ConfigUseCaseImpl()
        #expect(useCase.existingConfigPath == nil)
    }
}

@Test("watchChanges delegates to repository and passes onChange through")
func watchChangesDelegates() {
    let repository = WatchRecordingConfigRepository()
    let token = withDependencies {
        $0.configRepository = repository
    } operation: {
        let useCase = ConfigUseCaseImpl()
        return useCase.watchChanges { repository.onChangeFired.setTrue() }
    }

    #expect(token != nil)
    repository.fire()
    #expect(repository.onChangeFired.value)
}

// MARK: - Mocks

private struct MockConfigRepository: ConfigRepository {
    var style: AppStyle = .init()
    var templateResult: String?
    var writeTemplateResult: String = ""
    var configPath: String?
    var validation: ConfigValidationResult = .defaults

    func loadAppStyle() -> AppStyle { style }

    func validate(strictOptionalSections: Bool) -> ConfigValidationResult { validation }
    func template(format: ConfigFormat) -> String? { templateResult }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { writeTemplateResult }
    var existingConfigPath: String? { configPath }
}

/// Records the `watchChanges` subscription so the delegation test can verify the
/// use case passes `onChange` through to its adjacent repository untouched.
private final class WatchRecordingConfigRepository: ConfigRepository, @unchecked Sendable {
    let onChangeFired = LockedFlag()
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func fire() {
        lock.withLock { handler }?()
    }

    func loadAppStyle() -> AppStyle { .init() }
    func validate(strictOptionalSections: Bool) -> ConfigValidationResult { .defaults }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }

    func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock { handler = onChange }
        return NoopWatchToken()
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func setTrue() {
        lock.withLock { _value = true }
    }
}

private struct NoopWatchToken: ConfigWatchToken {
    func stop() {}
}

private final class CountingConfigRepository: ConfigRepository, @unchecked Sendable {
    var callCount = 0
    var validation: ConfigValidationResult = .loaded(path: "/c.toml")
    var pathExists = true

    /// The first load serves `initial.mp4`, later loads serve `reloaded.mp4`, so
    /// a test can assert which style the use case's store actually holds after a
    /// reload attempt — not just how many times the repository was called.
    func loadAppStyle() -> AppStyle {
        callCount += 1
        let location = callCount == 1 ? "initial.mp4" : "reloaded.mp4"
        return AppStyle(wallpaper: WallpaperStyle(location: location), configDir: "/config")
    }

    func validate(strictOptionalSections: Bool) -> ConfigValidationResult { validation }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { pathExists ? "/c.toml" : nil }
}
