import Foundation
import Testing

@testable import LyricsResolutionLog

@Suite("FileLyricsResolutionLog")
struct FileLyricsResolutionLogTests {
    @Test("configured path is used verbatim")
    func configuredPathVerbatim() {
        #expect(FileLyricsResolutionLog.resolvedPath(configured: "/tmp/lyra-x/log.txt") == "/tmp/lyra-x/log.txt")
    }

    @Test("tilde in configured path expands to home")
    func tildeExpands() {
        let expanded = FileLyricsResolutionLog.resolvedPath(configured: "~/lyra-debug.log")
        #expect(expanded == "\(NSHomeDirectory())/lyra-debug.log")
        #expect(!expanded.contains("~"))
    }

    @Test("nil configured path derives the cache default")
    func nilDerivesDefault() {
        #expect(FileLyricsResolutionLog.resolvedPath(configured: nil).hasSuffix("/lyra/lyrics-debug.log"))
    }

    @Test("blank configured path derives the cache default")
    func blankDerivesDefault() {
        #expect(FileLyricsResolutionLog.resolvedPath(configured: "   ").hasSuffix("/lyra/lyrics-debug.log"))
    }

    @Test("disabled log writes nothing")
    func disabledWritesNothing() {
        let path = Self.tempPath()
        FileLyricsResolutionLog(enabled: false, path: path).record("should not appear")
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("enabled log creates the file and appends successive blocks")
    func enabledAppendsBlocks() throws {
        let path = Self.tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let log = FileLyricsResolutionLog(enabled: true, path: path)
        log.record("block one")
        log.record("block two")
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents == "block one\nblock two\n")
    }

    @Test("a block that already ends in newline is not double-terminated")
    func trailingNewlineNotDuplicated() throws {
        let path = Self.tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let log = FileLyricsResolutionLog(enabled: true, path: path)
        log.record("already terminated\n")
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents == "already terminated\n")
    }

    private static func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-log-test-\(UUID().uuidString)")
            .appendingPathComponent("trace.log")
            .path
    }
}
