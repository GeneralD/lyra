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

        // イベントが確実に届くよう少し待ってから書込
        try await Task.sleep(for: .milliseconds(50))
        try "hello".write(to: dir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let deadline = ContinuousClock.now + .seconds(3)
        while !box.fired, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(box.fired)
    }
}

final class FiredBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _fired = false
    var fired: Bool { lock.withLock { _fired } }
    func fire() { lock.withLock { _fired = true } }
}
