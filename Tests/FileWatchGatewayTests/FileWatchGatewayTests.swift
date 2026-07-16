import Foundation
import Testing

@testable import FileWatchGateway

@Suite("FileWatchGateway")
struct FileWatchGatewayTests {
    @Test("ディレクトリ内のファイル書込で onChange が発火する")
    func firesOnWrite() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lyra-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let box = FiredBox()
        let token = FileWatchGateway().watch(directory: dir.path) { box.fire() }
        #expect(token != nil)
        defer { token?.stop() }

        // `watch(...)` resumes the DispatchSource before returning the token,
        // so the event source is already armed — write immediately and rely
        // on the poll-until-deadline loop below to wait for delivery.
        try "hello".write(to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let deadline = ContinuousClock.now + .seconds(3)
        while !box.fired, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(box.fired)
    }

    @Test("ファイルへの in-place 上書きで watch(file:) の onChange が発火する")
    func fileWatchFiresOnInPlaceWrite() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lyra-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.toml")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let box = FiredBox()
        let token = FileWatchGateway().watch(file: file.path) { box.fire() }
        #expect(token != nil)
        defer { token?.stop() }

        // In-place append: no rename, so a directory watch would never see this —
        // exactly the editor-save style that motivated the file-level watch.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" world".utf8))
        try handle.close()

        let deadline = ContinuousClock.now + .seconds(3)
        while !box.fired, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(box.fired)
    }

    @Test("watch(file:) は存在しないファイルでは nil を返す")
    func fileWatchReturnsNilForMissingFile() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lyra-watch-missing-\(UUID().uuidString).toml")
        #expect(FileWatchGateway().watch(file: missing.path) {} == nil)
    }
}

final class FiredBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _fired = false
    var fired: Bool { lock.withLock { _fired } }
    func fire() { lock.withLock { _fired = true } }
}
