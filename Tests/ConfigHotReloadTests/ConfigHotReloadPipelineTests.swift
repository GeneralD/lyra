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
import TestSupport
import Testing

/// Wires real `ConfigUseCaseImpl`, `ConfigInteractorImpl`, `ConfigRepositoryImpl`, and
/// `ConfigDataSourceImpl(configHome:)` instances against a temporary config file, then
/// manually fires a fake `ConfigWatchGateway` to verify the complete in-process
/// hot-reload pipeline for issue #41.
@Suite("Config Hot Reload — in-process pipeline E2E", .timeLimit(.minutes(1)))
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
        // Constructing dependency-owning types such as ConfigDataSourceImpl there would capture the
        // defaults instead. The overrides become ambient inside the operation closure, so construct
        // dependency-owning types one operation level deeper — the fake gateway sits outermost
        // because ConfigDataSourceImpl (the watch owner) captures it at construction.
        let (sharedUseCase, interactor): (ConfigUseCaseImpl, ConfigInteractorImpl) = withDependencies {
            $0.configWatchGateway = gateway
            $0.continuousClock = ImmediateClock()
        } operation: {
            withDependencies {
                $0.configDataSource = ConfigDataSourceImpl(configHome: xdgConfig.path)
            } operation: {
                withDependencies {
                    $0.configRepository = ConfigRepositoryImpl()
                } operation: {
                    let useCase = ConfigUseCaseImpl()
                    let interactor = withDependencies {
                        $0.configUseCase = useCase
                    } operation: {
                        ConfigInteractorImpl()
                    }
                    return (useCase, interactor)
                }
            }
        }

        // 1. Verify that config A is initially reflected in configUseCase.appStyle.
        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "a.mp4")

        // Recorded from Combine sink callbacks running on the interactor's worker
        // context (a nonisolated debounce `Task`, not MainActor) — Collector, not
        // settle(_:until:), is the spy for state written off the main actor (#349).
        let pings = Collector<Void>()
        let invalids = Collector<ConfigReloadFailure?>()
        let pingCancellable = interactor.appStyleChanges.sink { pings.append(()) }
        let invalidCancellable = interactor.invalidConfig.sink { invalids.append($0) }
        interactor.start()

        // 2. Write config B, fire the gateway, and verify appStyleChanges emits and appStyle reflects B.
        try configFile.write(#"wallpaper = "b.mp4""#)
        gateway.fire()

        await pings.waitForCount(1)
        await invalids.settle { $0.last == .some(nil) }
        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "b.mp4")

        // 3. Write invalid TOML, fire the gateway, and verify invalidConfig emits a failure
        //    while appStyle retains config B. `pings` only ever grows, so "no further ping"
        //    is checked as "count unchanged since before this write" rather than a reset flag.
        let pingsBeforeInvalidWrite = pings.count
        try configFile.write("wallpaper = [")
        gateway.fire()

        await invalids.settle { $0.last.map { $0 != nil } ?? false }
        let latestInvalid = invalids.last.flatMap { $0 }
        guard case .decode = latestInvalid?.reason else {
            Issue.record("expected .decode failure, got \(String(describing: latestInvalid))")
            return
        }
        // .invalid never sends appStyleChanges (see ConfigInteractorImpl.applyReload), so
        // once the failure above is observed, no ping from this reload can still be pending.
        #expect(pings.count == pingsBeforeInvalidWrite)
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
            $0.configWatchGateway = gateway
            $0.continuousClock = ImmediateClock()
        } operation: {
            withDependencies {
                $0.configDataSource = ConfigDataSourceImpl(configHome: xdgConfig.path)
            } operation: {
                withDependencies {
                    $0.configRepository = ConfigRepositoryImpl()
                } operation: {
                    let useCase = ConfigUseCaseImpl()
                    let interactor = withDependencies {
                        $0.configUseCase = useCase
                    } operation: {
                        ConfigInteractorImpl()
                    }
                    return (useCase, interactor)
                }
            }
        }

        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "a.mp4")

        // Recorded from Combine sink callbacks running on the interactor's worker
        // context (a nonisolated debounce `Task`, not MainActor) — Collector, not
        // settle(_:until:), is the spy for state written off the main actor (#349).
        let pings = Collector<Void>()
        let invalids = Collector<ConfigReloadFailure?>()
        let pingCancellable = interactor.appStyleChanges.sink { pings.append(()) }
        let invalidCancellable = interactor.invalidConfig.sink { invalids.append($0) }
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

        await pings.waitForCount(1)
        await invalids.settle { $0.last == .some(nil) }
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

    // The pipeline tests drive reloads through the directory event only; the
    // file-level watch is exercised in ConfigWatchTests (ConfigDataSourceTests).
    func watch(file: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        FakeConfigWatchToken()
    }

    func fire() {
        lock.withLock { handler }?()
    }
}

private struct FakeConfigWatchToken: ConfigWatchToken {
    func stop() {}
}
