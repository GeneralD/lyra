import Dependencies
import Domain
import FileWatchGateway
import Foundation
import Testing

@testable import ConfigDataSource

@Suite("ConfigDataSourceImpl.watchChanges")
struct ConfigWatchTests {
    private let tempDir: String = NSTemporaryDirectory() + "lyra-watch-test-\(UUID().uuidString)"

    private func setUpLyraDir(files: [String: String]) throws -> String {
        let lyraDir = tempDir + "/lyra"
        try FileManager.default.createDirectory(atPath: lyraDir, withIntermediateDirectories: true)
        for (name, content) in files {
            try content.write(toFile: lyraDir + "/\(name)", atomically: true, encoding: .utf8)
        }
        return lyraDir
    }

    private func tearDown() {
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    @Test("config dir・config file・includes・外部 include の親 dir が watch される")
    func armsFullWatchSurface() throws {
        defer { tearDown() }

        let outsideDir = tempDir + "/outside"
        try FileManager.default.createDirectory(atPath: outsideDir, withIntermediateDirectories: true)
        try "screen = \"main\"".write(toFile: outsideDir + "/shared.toml", atomically: true, encoding: .utf8)
        _ = try setUpLyraDir(files: [
            "config.toml": "includes = [\"koko.toml\", \"\(outsideDir)/shared.toml\"]",
            "koko.toml": "screen = \"main\"",
        ])

        let gateway = FakeWatchGateway()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges {}
        }
        defer { token?.stop() }

        #expect(token != nil)
        let directories = gateway.watchedDirectories
        #expect(directories.count == 2)
        #expect(directories.contains { $0.hasSuffix("/lyra/") })
        #expect(directories.contains { $0.hasSuffix("/outside/") })
        let files = gateway.watchedFiles
        #expect(files.count == 3)
        #expect(files.contains { $0.hasSuffix("/lyra/config.toml") })
        #expect(files.contains { $0.hasSuffix("/lyra/koko.toml") })
        #expect(files.contains { $0.hasSuffix("/outside/shared.toml") })
    }

    @Test("同一ディレクトリ内の include では config dir が二重 watch されない（末尾スラッシュ回帰）")
    func doesNotDoubleWatchConfigDirectory() throws {
        defer { tearDown() }

        _ = try setUpLyraDir(files: [
            "config.toml": "includes = [\"koko.toml\"]",
            "koko.toml": "screen = \"main\"",
        ])

        let gateway = FakeWatchGateway()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges {}
        }
        defer { token?.stop() }

        #expect(gateway.watchedDirectories.count == 1)
    }

    @Test("欠損 include も watch 対象に残る — 外部 include の親 dir が watch され、後からの作成を拾える")
    func keepsMissingIncludesInWatchTargets() throws {
        defer { tearDown() }

        let outsideDir = tempDir + "/outside"
        try FileManager.default.createDirectory(atPath: outsideDir, withIntermediateDirectories: true)
        // Neither include exists yet. The foreign parent directory must still be
        // watched so creating shared.toml later fires an event; the missing
        // same-directory include is covered by the config-directory watch.
        _ = try setUpLyraDir(files: [
            "config.toml": "includes = [\"missing.toml\", \"\(outsideDir)/shared.toml\"]"
        ])

        let gateway = FakeWatchGateway()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges {}
        }
        defer { token?.stop() }

        #expect(gateway.watchedDirectories.contains { $0.hasSuffix("/outside/") })
        #expect(gateway.watchedFiles.contains { $0.hasSuffix("/lyra/missing.toml") })
        #expect(gateway.watchedFiles.contains { $0.hasSuffix("/outside/shared.toml") })
    }

    @Test("config dir を watch できないときは nil を返し file watch も張らない")
    func returnsNilWhenDirectoryUnwatchable() throws {
        defer { tearDown() }

        _ = try setUpLyraDir(files: ["config.toml": "screen = \"main\""])

        let gateway = FakeWatchGateway(directoryWatchable: false)
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges {}
        }

        #expect(token == nil)
        #expect(gateway.watchedFiles.isEmpty)
    }

    @Test("file 不在で arm 後、作成を directory イベントで拾って file watch が張られる（#329）")
    func armsFileWatchOnceConfigAppears() throws {
        defer { tearDown() }

        let lyraDir = try setUpLyraDir(files: [:])

        let gateway = FakeWatchGateway()
        let onChange = Counter()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges { onChange.increment() }
        }
        defer { token?.stop() }

        #expect(token != nil)
        #expect(gateway.watchedFiles.isEmpty)

        // `lyra config init` (or a manual save) creates the file; the directory
        // watch reports it and the re-arm picks it up from disk.
        try "screen = \"main\"".write(toFile: lyraDir + "/config.toml", atomically: true, encoding: .utf8)
        gateway.fireDirectoryHandlers()

        #expect(gateway.watchedFiles.contains { $0.hasSuffix("/lyra/config.toml") })
        #expect(onChange.count == 1)
    }

    @Test("イベント毎に file watch が再アームされ、古い token は stop される")
    func rearmsFileTierOnEveryEvent() throws {
        defer { tearDown() }

        _ = try setUpLyraDir(files: ["config.toml": "screen = \"main\""])

        let gateway = FakeWatchGateway()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges {}
        }
        defer { token?.stop() }

        #expect(gateway.watchedFiles.count == 1)
        gateway.fireDirectoryHandlers()  // Atomic save: the old file fd is dead.

        #expect(gateway.watchedFiles.count == 2)
        #expect(gateway.stoppedTokenCount == 1)
    }

    @Test("stop() 後はイベントが来ても再アームも onChange もされない")
    func stopSilencesSession() throws {
        defer { tearDown() }

        _ = try setUpLyraDir(files: ["config.toml": "screen = \"main\""])

        let gateway = FakeWatchGateway()
        let onChange = Counter()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges { onChange.increment() }
        }

        token?.stop()
        let armedBeforeFire = gateway.watchedFiles.count
        gateway.fireDirectoryHandlers()

        #expect(onChange.count == 0)
        #expect(gateway.watchedFiles.count == armedBeforeFire)
    }

    @Test("実 FS: include の in-place 編集・atomic save 後の再編集が onChange を発火する")
    func liveGatewayObservesIncludeEditsAndSurvivesAtomicSave() async throws {
        defer { tearDown() }

        let lyraDir = try setUpLyraDir(files: [
            "config.toml": "includes = [\"koko.toml\"]",
            "koko.toml": "screen = \"main\"",
        ])

        let onChange = Counter()
        let token = withDependencies {
            $0.configWatchGateway = FileWatchGateway()
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges { onChange.increment() }
        }
        defer { token?.stop() }
        #expect(token != nil)

        // 1. In-place append to the include file — only its file-level watch sees this.
        let includeHandle = FileHandle(forWritingAtPath: lyraDir + "/koko.toml")
        try includeHandle?.seekToEnd()
        try includeHandle?.write(contentsOf: Data("\n# edited\n".utf8))
        try includeHandle?.close()

        let firstDeadline = ContinuousClock.now + .seconds(3)
        while onChange.count < 1, ContinuousClock.now < firstDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(onChange.count >= 1)

        // 2. Atomic save of the main config (fresh inode renamed into place),
        //    then an in-place append to the NEW inode: only a re-armed file
        //    watch can observe the second edit.
        try "includes = [\"koko.toml\"]\nscreen = \"main\"".write(
            toFile: lyraDir + "/config.toml", atomically: true, encoding: .utf8)
        let afterRename = onChange.count
        let renameDeadline = ContinuousClock.now + .seconds(3)
        while onChange.count == afterRename, ContinuousClock.now < renameDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let settled = onChange.count
        let configHandle = FileHandle(forWritingAtPath: lyraDir + "/config.toml")
        try configHandle?.seekToEnd()
        try configHandle?.write(contentsOf: Data("\n# in-place after rename\n".utf8))
        try configHandle?.close()

        let secondDeadline = ContinuousClock.now + .seconds(3)
        while onChange.count <= settled, ContinuousClock.now < secondDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(onChange.count > settled)
    }
}

// MARK: - Fakes

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func increment() {
        lock.withLock { _count += 1 }
    }
}

private final class FakeWatchGateway: ConfigWatchGateway, @unchecked Sendable {
    private let lock = NSLock()
    private let directoryWatchable: Bool
    private var _watchedDirectories: [String] = []
    private var _watchedFiles: [String] = []
    private var directoryHandlers: [@Sendable () -> Void] = []
    private var _stoppedTokenCount = 0

    init(directoryWatchable: Bool = true) {
        self.directoryWatchable = directoryWatchable
    }

    var watchedDirectories: [String] { lock.withLock { _watchedDirectories } }
    var watchedFiles: [String] { lock.withLock { _watchedFiles } }
    var stoppedTokenCount: Int { lock.withLock { _stoppedTokenCount } }

    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock {
            guard directoryWatchable else { return nil }
            _watchedDirectories.append(directory)
            directoryHandlers.append(onChange)
            return FakeToken { [weak self] in self?.recordStop() }
        }
    }

    func watch(file: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock {
            _watchedFiles.append(file)
            return FakeToken { [weak self] in self?.recordStop() }
        }
    }

    func fireDirectoryHandlers() {
        for handler in lock.withLock({ directoryHandlers }) { handler() }
    }

    private func recordStop() {
        lock.withLock { _stoppedTokenCount += 1 }
    }
}

private struct FakeToken: ConfigWatchToken {
    let onStop: @Sendable () -> Void
    func stop() { onStop() }
}
