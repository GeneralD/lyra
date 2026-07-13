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

/// 実 `ConfigUseCaseImpl` + 実 `ConfigInteractorImpl` + 実 `ConfigRepositoryImpl` +
/// 実 `ConfigDataSourceImpl(configHome:)` を temp config ファイル上で結線し、
/// fake の `ConfigWatchGateway` を手動 fire してホットリロードの in-process
/// パイプライン全体を検証する E2E テスト（issue #41）。
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

        // すべて operation クロージャ内で構築（swift-dependencies のコンテキスト捕捉のため）。
        // ConfigInteractorImpl は sharedUseCase をそのまま configUseCase として受け取るので、
        // テストが観測する appStyle と interactor が reload() する対象は同一インスタンス。
        //
        // withDependencies の「update values」クロージャはまだ ambient(TaskLocal)に反映される
        // 前に評価されるため、依存を持つ型（ConfigRepositoryImpl 等）をそこで構築すると自身の
        // @Dependency が override 前の default を捕まえてしまう。次段の operation クロージャに
        // 入って初めて ambient に反映されるので、依存を持つ型は一段深い operation 内で構築する。
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

        // 1. 初期状態で configUseCase.appStyle が config A を反映
        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "a.mp4")

        final class Observed: @unchecked Sendable {
            var pinged = false
            var lastInvalid: ConfigReloadFailure?
        }
        let observed = Observed()
        let pingCancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        let invalidCancellable = interactor.invalidConfig.sink { observed.lastInvalid = $0 }
        interactor.start()

        // 2. config を B に書き換え → gateway.fire() → appStyleChanges が発火し appStyle が B を反映
        try configFile.write(#"wallpaper = "b.mp4""#)
        gateway.fire()

        let updateDeadline = ContinuousClock.now + .seconds(3)
        while !observed.pinged, ContinuousClock.now < updateDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.pinged)
        #expect(observed.lastInvalid == nil)
        #expect(sharedUseCase.appStyle.wallpaper?.items.first?.location == "b.mp4")

        // 3. config を不正な TOML に書き換え → gateway.fire() → invalidConfig に failure が流れ、
        //    appStyle は B のまま（前回値保持）
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
