import Combine
import ConfigDataSource
import ConfigInteractor
import ConfigRepository
import ConfigUseCase
import Dependencies
import Domain
import Entity
import Files
import Foundation
import Testing

/// Wires real `ConfigUseCaseImpl`, `ConfigInteractorImpl`, `ConfigRepositoryImpl`, and
/// `ConfigDataSourceImpl(configHome:)` instances against a temporary config file, then
/// manually fires a fake `ConfigWatchGateway` to verify the complete in-process
/// hot-reload pipeline for issue #41.
@Suite("Config Hot Reload — in-process pipeline E2E")
struct ConfigHotReloadPipelineTests {
    @Test("初期状態は config A、B へ書換 + fire でホットリロード成立、不正 config は前回値保持")
    func hotReloadPipeline() async throws {
        let xdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        defer { try? xdgConfig.delete() }
        let lyraDir = try xdgConfig.createSubfolder(named: "lyra")
        let configFile = try lyraDir.createFile(named: "config.toml")
        try configFile.write(#"wallpaper = "a.mp4""#)

        let gateway = FakeConfigWatchGateway()

        // Construct everything inside operation closures so swift-dependencies captures the context.
        // ConfigInteractorImpl receives sharedUseCase as its configUseCase, so the appStyle observed
        // by the test and the instance reloaded by the interactor are identical.
        //
        // The withDependencies update closure runs before its overrides enter the ambient TaskLocal.
        // Constructing dependency-owning types such as ConfigRepositoryImpl there would capture the
        // defaults instead. The overrides become ambient inside the operation closure, so construct
        // dependency-owning types one operation level deeper.
        let (sharedUseCase, interactor): (ConfigUseCaseImpl, ConfigInteractorImpl) = withDependencies {
            $0.configDataSource = ConfigDataSourceImpl(configHome: xdgConfig.path)
            $0.continuousClock = ImmediateClock()
        } operation: {
            withDependencies {
                $0.configRepository = ConfigRepositoryImpl()
            } operation: {
                let useCase = ConfigUseCaseImpl()
                let interactor = withDependencies {
                    $0.configUseCase = useCase
                    $0.configWatchGateway = gateway
                } operation: {
                    ConfigInteractorImpl()
                }
                return (useCase, interactor)
            }
        }

        // 1. Verify that config A is initially reflected in configUseCase.appStyle.
        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "a.mp4")

        final class Observed: @unchecked Sendable {
            var pinged = false
            var lastInvalid: ConfigReloadFailure?
        }
        let observed = Observed()
        let pingCancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        let invalidCancellable = interactor.invalidConfig.sink { observed.lastInvalid = $0 }
        interactor.start()

        // 2. Write config B, fire the gateway, and verify appStyleChanges emits and appStyle reflects B.
        try configFile.write(#"wallpaper = "b.mp4""#)
        gateway.fire()

        let updateDeadline = ContinuousClock.now + .seconds(3)
        while !observed.pinged, ContinuousClock.now < updateDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.pinged)
        #expect(observed.lastInvalid == nil)
        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "b.mp4")

        // 3. Write invalid TOML, fire the gateway, and verify invalidConfig emits a failure
        //    while appStyle retains config B.
        observed.pinged = false
        try configFile.write("wallpaper = [")
        gateway.fire()

        let invalidDeadline = ContinuousClock.now + .seconds(3)
        while observed.lastInvalid == nil, ContinuousClock.now < invalidDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard case .decode = observed.lastInvalid?.reason else {
            Issue.record("expected .decode failure, got \(String(describing: observed.lastInvalid))")
            return
        }
        #expect(!observed.pinged)
        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "b.mp4")

        pingCancellable.cancel()
        invalidCancellable.cancel()
        interactor.stop()
    }

    @Test("optional セクション（[lyrics]）のみ不正な編集は起動時同様に縮退し、有効な wallpaper 編集は反映される (#330)")
    func lenientOptionalSectionReload() async throws {
        let xdgConfig = try Folder.temporary.createSubfolder(named: UUID().uuidString)
        defer { try? xdgConfig.delete() }
        let lyraDir = try xdgConfig.createSubfolder(named: "lyra")
        let configFile = try lyraDir.createFile(named: "config.toml")
        try configFile.write(#"wallpaper = "a.mp4""#)

        let gateway = FakeConfigWatchGateway()

        let (sharedUseCase, interactor): (ConfigUseCaseImpl, ConfigInteractorImpl) = withDependencies {
            $0.configDataSource = ConfigDataSourceImpl(configHome: xdgConfig.path)
            $0.continuousClock = ImmediateClock()
        } operation: {
            withDependencies {
                $0.configRepository = ConfigRepositoryImpl()
            } operation: {
                let useCase = ConfigUseCaseImpl()
                let interactor = withDependencies {
                    $0.configUseCase = useCase
                    $0.configWatchGateway = gateway
                } operation: {
                    ConfigInteractorImpl()
                }
                return (useCase, interactor)
            }
        }

        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "a.mp4")

        final class Observed: @unchecked Sendable {
            var pinged = false
            var lastInvalid: ConfigReloadFailure?
        }
        let observed = Observed()
        let pingCancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        let invalidCancellable = interactor.invalidConfig.sink { observed.lastInvalid = $0 }
        interactor.start()

        // Edit wallpaper to b.mp4 while introducing a structurally invalid [lyrics]
        // section (a string where an argv array is required). The optional section
        // must degrade like startup — hot-reload should apply the valid wallpaper
        // rather than reject the whole edit and keep a.mp4.
        try configFile.write(
            """
            wallpaper = "b.mp4"

            [lyrics]
            fallback_command = "/not/an/argv/array"
            """)
        gateway.fire()

        let deadline = ContinuousClock.now + .seconds(3)
        while !observed.pinged, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.pinged)
        #expect(observed.lastInvalid == nil)
        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "b.mp4")

        pingCancellable.cancel()
        invalidCancellable.cancel()
        interactor.stop()
    }
}

// MARK: - Fake

private final class FakeConfigWatchGateway: ConfigWatchGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock { handler = onChange }
        return FakeConfigWatchToken()
    }

    func fire() {
        lock.withLock { handler }?()
    }
}

private struct FakeConfigWatchToken: ConfigWatchToken {
    func stop() {}
}
