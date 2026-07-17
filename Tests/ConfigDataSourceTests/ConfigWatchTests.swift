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

    @Test("config dir 不在でも最も近い実在祖先に park して armed になる（#338）")
    func parksOnNearestAncestorWhenConfigDirMissing() throws {
        defer { tearDown() }

        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let gateway = FakeWatchGateway()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges {}
        }
        defer { token?.stop() }

        #expect(token != nil)
        #expect(gateway.watchedDirectories == [tempDir])
        #expect(gateway.watchedFiles.isEmpty)
    }

    @Test("祖先イベントで config dir 出現 → watch 昇格・file watch・initial load 発火（#338）")
    func promotesToConfigDirOnceCreated() throws {
        defer { tearDown() }

        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let gateway = FakeWatchGateway()
        let onChange = Counter()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges { onChange.increment() }
        }
        defer { token?.stop() }

        _ = try setUpLyraDir(files: ["config.toml": "screen = \"main\""])
        gateway.fireDirectoryHandlers()

        #expect(gateway.watchedDirectories.contains { $0.hasSuffix("/lyra/") })
        #expect(gateway.watchedFiles.contains { $0.hasSuffix("/lyra/config.toml") })
        #expect(onChange.count == 1)

        // Promoted for real: a subsequent config-directory event flows as usual.
        gateway.fireDirectoryHandlers()
        #expect(onChange.count == 2)
    }

    @Test("目的パスが現れない祖先イベントは onChange を発火しない（ノイズフィルタ、#338）")
    func ancestorNoiseDoesNotFireOnChange() throws {
        defer { tearDown() }

        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let gateway = FakeWatchGateway()
        let onChange = Counter()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges { onChange.increment() }
        }
        defer { token?.stop() }

        gateway.fireDirectoryHandlers()  // Unrelated churn beneath the ancestor.

        #expect(onChange.count == 0)
        #expect(gateway.watchedFiles.isEmpty)

        // The park must survive the noise: a later creation still promotes.
        _ = try setUpLyraDir(files: ["config.toml": "screen = \"main\""])
        gateway.fireDirectoryHandlers()
        #expect(onChange.count == 1)
    }

    @Test("中間ディレクトリのみ出現 → より近い祖先へ park し直し、onChange なし（#338）")
    func walksDownToNearerAncestorWithoutFiring() throws {
        defer { tearDown() }

        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let configRoot = tempDir + "/cfgroot"

        let gateway = FakeWatchGateway()
        let onChange = Counter()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: configRoot).watchChanges { onChange.increment() }
        }
        defer { token?.stop() }

        #expect(gateway.watchedDirectories.last == tempDir)

        try FileManager.default.createDirectory(atPath: configRoot, withIntermediateDirectories: true)
        gateway.fireDirectoryHandlers()

        #expect(onChange.count == 0)
        #expect(gateway.watchedDirectories.last == configRoot)

        try FileManager.default.createDirectory(atPath: configRoot + "/lyra", withIntermediateDirectories: true)
        try "screen = \"main\"".write(toFile: configRoot + "/lyra/config.toml", atomically: true, encoding: .utf8)
        gateway.fireDirectoryHandlers()

        #expect(onChange.count == 1)
        #expect(gateway.watchedDirectories.last?.hasSuffix("/lyra/") == true)
        #expect(gateway.watchedFiles.contains { $0.hasSuffix("/lyra/config.toml") })
    }

    @Test("稼働中に config dir が消えたら祖先へ降格 park し、再作成で復帰する（#338）")
    func demotesWhenConfigDirDeletedAndRecoversOnRecreation() throws {
        defer { tearDown() }

        let lyraDir = try setUpLyraDir(files: ["config.toml": "screen = \"main\""])

        let gateway = FakeWatchGateway()
        let onChange = Counter()
        let token = withDependencies {
            $0.configWatchGateway = gateway
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges { onChange.increment() }
        }
        defer { token?.stop() }

        try FileManager.default.removeItem(atPath: lyraDir)
        gateway.fireDirectoryHandlers()  // The dead directory fd's final .delete event.

        #expect(onChange.count == 1)  // Reload-to-defaults ping.
        #expect(gateway.watchedDirectories.last == tempDir)

        _ = try setUpLyraDir(files: ["config.toml": "screen = \"main\""])
        gateway.fireDirectoryHandlers()

        #expect(onChange.count == 2)
        #expect(gateway.watchedDirectories.last?.hasSuffix("/lyra/") == true)
        #expect(gateway.watchedFiles.last?.hasSuffix("/lyra/config.toml") == true)
    }

    @Test("directoryAncestors は近い順に / まで列挙する（純関数）")
    func directoryAncestorsEnumeratesNearestFirst() {
        #expect(directoryAncestors(of: "/a/b/c") == ["/a/b", "/a", "/"])
        #expect(directoryAncestors(of: "/a/b/c/") == ["/a/b", "/a", "/"])
        #expect(directoryAncestors(of: "/a") == ["/"])
        #expect(directoryAncestors(of: "/") == [])
    }

    @Test("実 FS: config dir を後から作成しても watch が昇格して onChange が発火する（#338）")
    func liveGatewayPromotesWhenConfigDirCreatedLater() async throws {
        defer { tearDown() }

        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let onChange = Counter()
        let token = withDependencies {
            $0.configWatchGateway = FileWatchGateway()
        } operation: {
            ConfigDataSourceImpl(configHome: tempDir).watchChanges { onChange.increment() }
        }
        defer { token?.stop() }
        #expect(token != nil)

        // First run of `lyra config init`: directory and file appear together.
        let lyraDir = try setUpLyraDir(files: ["config.toml": "screen = \"main\""])

        let promoteDeadline = ContinuousClock.now + .seconds(3)
        while onChange.count < 1, ContinuousClock.now < promoteDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(onChange.count >= 1)

        // The promoted session must have armed the file tier: an in-place
        // append is visible only to a file-level watch.
        let settled = onChange.count
        let handle = FileHandle(forWritingAtPath: lyraDir + "/config.toml")
        try handle?.seekToEnd()
        try handle?.write(contentsOf: Data("\n# edited\n".utf8))
        try handle?.close()

        let editDeadline = ContinuousClock.now + .seconds(3)
        while onChange.count <= settled, ContinuousClock.now < editDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(onChange.count > settled)
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
    private var liveDirectoryHandlers: [UUID: @Sendable () -> Void] = [:]
    private var _stoppedTokenCount = 0

    init(directoryWatchable: Bool = true) {
        self.directoryWatchable = directoryWatchable
    }

    var watchedDirectories: [String] { lock.withLock { _watchedDirectories } }
    var watchedFiles: [String] { lock.withLock { _watchedFiles } }
    var stoppedTokenCount: Int { lock.withLock { _stoppedTokenCount } }

    /// Mirrors the live gateway: a directory watch only arms when the
    /// directory exists on disk (`open(2)` fails otherwise), which is what
    /// the ancestor-park fallback (#338) keys on.
    func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock {
            var isDirectory: ObjCBool = false
            guard directoryWatchable,
                FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { return nil }
            let id = UUID()
            _watchedDirectories.append(directory)
            liveDirectoryHandlers[id] = onChange
            return FakeToken { [weak self] in self?.stopDirectoryWatch(id) }
        }
    }

    func watch(file: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        lock.withLock {
            _watchedFiles.append(file)
            return FakeToken { [weak self] in self?.recordStop() }
        }
    }

    /// Fires only the handlers of directory watches still alive — a cancelled
    /// DispatchSource delivers no further events.
    func fireDirectoryHandlers() {
        for handler in lock.withLock({ Array(liveDirectoryHandlers.values) }) { handler() }
    }

    private func stopDirectoryWatch(_ id: UUID) {
        lock.withLock {
            liveDirectoryHandlers[id] = nil
            _stoppedTokenCount += 1
        }
    }

    private func recordStop() {
        lock.withLock { _stoppedTokenCount += 1 }
    }
}

private struct FakeToken: ConfigWatchToken {
    let onStop: @Sendable () -> Void
    func stop() { onStop() }
}
