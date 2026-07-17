import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import ConfigInteractor

@Suite("ConfigInteractorImpl")
struct ConfigInteractorImplTests {
    @Test(".updated で appStyleChanges が発火し invalidConfig が nil になる")
    func firesPingOnUpdate() async {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        final class Observed: @unchecked Sendable {
            var pinged = false
            var lastInvalid: ConfigReloadFailure?
        }
        let observed = Observed()
        let pingCancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        let invalidCancellable = interactor.invalidConfig.sink { observed.lastInvalid = $0 }
        interactor.start()
        gateway.fire()  // Emit a watch event.

        let deadline = ContinuousClock.now + .seconds(2)
        while !observed.pinged, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.pinged)
        #expect(observed.lastInvalid == nil)
        pingCancellable.cancel()
        invalidCancellable.cancel()
        interactor.stop()
    }

    @Test(".invalid で invalidConfig に failure が流れ ping は出ない")
    func surfacesFailureOnInvalid() async {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .invalid(.init(path: "/c.toml", reason: .decode("bad"))))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        final class Observed: @unchecked Sendable {
            var invalid: ConfigReloadFailure?
            var pinged = false
        }
        let observed = Observed()
        let invalidCancellable = interactor.invalidConfig.sink { observed.invalid = $0 }
        let pingCancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        interactor.start()
        gateway.fire()

        let deadline = ContinuousClock.now + .seconds(2)
        while observed.invalid == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.invalid?.reason == .decode("bad"))
        #expect(!observed.pinged)
        invalidCancellable.cancel()
        pingCancellable.cancel()
        interactor.stop()
    }

    @Test("start() を複数回呼んでも watch は一度しか張られない（冪等性）")
    func startIsIdempotent() {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()
        interactor.start()
        interactor.start()

        #expect(gateway.watchCallCount == 1)
        interactor.stop()
    }

    @Test("stop() 後に pending の debounce が発火しても publish されない（teardown race）")
    func stopSuppressesPendingReload() async {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let testClock = TestClock()
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = testClock
        } operation: {
            ConfigInteractorImpl()
        }

        final class Observed: @unchecked Sendable {
            var pinged = false
        }
        let observed = Observed()
        let cancellable = interactor.appStyleChanges.sink { observed.pinged = true }

        interactor.start()
        gateway.fire()  // The debounce task is now pending on clock.sleep.
        interactor.stop()  // Cancels: the sleep throws and the task still reaches applyReload.

        // The woken task must bail on the armed/cancelled guard instead of
        // publishing a spurious update after teardown.
        for _ in 0..<20 { await Task.yield() }
        #expect(!observed.pinged)
        cancellable.cancel()
    }

    @Test("config ファイルが無くても configDir を監視する（初回作成をホットリロードで拾う #329）")
    func armsWatchOnConfigDirectoryWhenFileAbsent() {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(
            outcome: .updated(.init(configDir: "/x")),
            existingConfigPath: nil,
            configDir: "/tmp/lyra")
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()

        // No config file yet, but the directory watch is still armed (early-return removed).
        #expect(gateway.watchCallCount == 1)
        #expect(gateway.watchedDirectory == "/tmp/lyra")
        // The file-level watch has nothing to attach to yet.
        #expect(gateway.watchFileCallCount == 0)
        interactor.stop()
    }

    @Test("start() で directory と file の両方の watch が張られる")
    func armsBothWatchesOnStart() {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()

        #expect(gateway.watchCallCount == 1)
        #expect(gateway.watchFileCallCount == 1)
        #expect(gateway.watchedFile == "/tmp/config.toml")
        interactor.stop()
    }

    @Test("file イベント（in-place 上書き保存）でも reload が走る")
    func reloadsOnFileEvent() async {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        final class Observed: @unchecked Sendable {
            var pinged = false
        }
        let observed = Observed()
        let cancellable = interactor.appStyleChanges.sink { observed.pinged = true }
        interactor.start()
        gateway.fireFile()  // In-place overwrite: only the file-level watch sees it.

        let deadline = ContinuousClock.now + .seconds(2)
        while !observed.pinged, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.pinged)
        cancellable.cancel()
        interactor.stop()
    }

    @Test("reload 後に file watch が再アームされる（atomic save で fd が無効化されるため）")
    func rearmsFileWatchAfterReload() async {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(outcome: .updated(.init(configDir: "/x")))
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()
        #expect(gateway.watchFileCallCount == 1)
        gateway.fire()  // Atomic save: directory event, old file fd is now dead.

        let deadline = ContinuousClock.now + .seconds(2)
        while gateway.watchFileCallCount < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(gateway.watchFileCallCount == 2)
        interactor.stop()
    }

    @Test("file 不在で start 後、作成を reload で拾って file watch が armed される（#329）")
    func armsFileWatchOnceConfigAppears() async {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(
            outcome: .updated(.init(configDir: "/x")),
            existingConfigPath: nil)
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()
        #expect(gateway.watchFileCallCount == 0)

        useCase.pathBox.path = "/tmp/config.toml"  // `lyra config init` created the file.
        gateway.fire()  // The directory watch reports the creation.

        let deadline = ContinuousClock.now + .seconds(2)
        while gateway.watchFileCallCount < 1, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(gateway.watchFileCallCount == 1)
        #expect(gateway.watchedFile == "/tmp/config.toml")
        interactor.stop()
    }

    @Test("includes 先のファイルも file watch される")
    func armsFileWatchesOnIncludedFiles() {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(
            outcome: .updated(.init(configDir: "/x")),
            existingConfigPath: "/tmp/lyra/config.toml",
            includedConfigPaths: ["/tmp/lyra/koko.toml"])
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()

        #expect(gateway.watchedFiles == ["/tmp/lyra/config.toml", "/tmp/lyra/koko.toml"])
        // The include lives inside configDir, already covered by the main directory watch.
        #expect(gateway.watchCallCount == 1)
        interactor.stop()
    }

    @Test("末尾スラッシュ付き configDir でも同一ディレクトリの include が二重 watch されない")
    func normalizesTrailingSlashWhenComparingIncludeParents() {
        let gateway = FakeConfigWatchGateway()
        // The live configDir (a Files-style folder path) carries a trailing slash.
        let useCase = StubConfigUseCase(
            outcome: .updated(.init(configDir: "/x")),
            existingConfigPath: "/tmp/lyra/config.toml",
            configDir: "/tmp/lyra/",
            includedConfigPaths: ["/tmp/lyra/koko.toml"])
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()

        #expect(gateway.watchCallCount == 1)
        interactor.stop()
    }

    @Test("configDir 外の include は親ディレクトリも watch される（atomic save 対策）")
    func armsDirectoryWatchOnForeignIncludeParent() {
        let gateway = FakeConfigWatchGateway()
        let useCase = StubConfigUseCase(
            outcome: .updated(.init(configDir: "/x")),
            existingConfigPath: "/tmp/lyra/config.toml",
            includedConfigPaths: ["/elsewhere/shared.toml"])
        let interactor = withDependencies {
            $0.configWatchGateway = gateway
            $0.configUseCase = useCase
            $0.continuousClock = ImmediateClock()
        } operation: {
            ConfigInteractorImpl()
        }

        interactor.start()

        #expect(gateway.watchedFiles == ["/tmp/lyra/config.toml", "/elsewhere/shared.toml"])
        #expect(gateway.watchedDirectories == ["/tmp/lyra", "/elsewhere"])
        interactor.stop()
    }
}

// MARK: - Fakes / Stubs

private final class FakeConfigWatchGateway: ConfigWatchGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private var fileHandlers: [@Sendable () -> Void] = []
    private var _watchCallCount = 0
    private var _watchFileCallCount = 0
    private var _watchedDirectories: [String] = []
    private var _watchedFiles: [String] = []

    var watchCallCount: Int { lock.withLock { _watchCallCount } }
    var watchFileCallCount: Int { lock.withLock { _watchFileCallCount } }
    var watchedDirectory: String? { lock.withLock { _watchedDirectories.first } }
    var watchedDirectories: [String] { lock.withLock { _watchedDirectories } }
    var watchedFile: String? { lock.withLock { _watchedFiles.first } }
    var watchedFiles: [String] { lock.withLock { _watchedFiles } }

    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock {
            handler = onChange
            _watchCallCount += 1
            _watchedDirectories.append(directory)
        }
        return FakeConfigWatchToken()
    }

    func watch(file: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock {
            fileHandlers.append(onChange)
            _watchFileCallCount += 1
            _watchedFiles.append(file)
        }
        return FakeConfigWatchToken()
    }

    func fire() {
        lock.withLock { handler }?()
    }

    func fireFile() {
        for handler in lock.withLock({ fileHandlers }) { handler() }
    }
}

private struct FakeConfigWatchToken: ConfigWatchToken {
    func stop() {}
}

/// Reference box so a test can change the stub's `existingConfigPath` after the
/// interactor captured the (value-type) stub — models a config file created later.
private final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _path: String?
    init(_ path: String?) { _path = path }
    var path: String? {
        get { lock.withLock { _path } }
        set { lock.withLock { _path = newValue } }
    }
}

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    let outcome: ConfigReloadOutcome
    let pathBox: PathBox
    let configDir: String  // The watched directory — resolved regardless of file existence (#329).
    let includedConfigPaths: [String]

    init(
        outcome: ConfigReloadOutcome,
        existingConfigPath: String? = "/tmp/config.toml",
        configDir: String = "/tmp/lyra",
        includedConfigPaths: [String] = []
    ) {
        self.outcome = outcome
        self.pathBox = PathBox(existingConfigPath)
        self.configDir = configDir
        self.includedConfigPaths = includedConfigPaths
    }

    var existingConfigPath: String? { pathBox.path }
    var appStyle: AppStyle { .init() }
    func reload() -> ConfigReloadOutcome { outcome }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
}
