import Foundation
import Testing

@testable import DeveloperLog

@Suite("FileDeveloperLog")
struct FileDeveloperLogTests {
    @Test("configured path is used verbatim")
    func configuredPathVerbatim() {
        #expect(
            FileDeveloperLog.resolvedPath(configured: "/tmp/lyra-x/log.txt", defaultFilename: "lyrics-debug.log")
                == "/tmp/lyra-x/log.txt")
    }

    @Test("tilde in configured path expands to home")
    func tildeExpands() {
        let expanded = FileDeveloperLog.resolvedPath(configured: "~/lyra-debug.log", defaultFilename: "lyrics-debug.log")
        #expect(expanded == "\(NSHomeDirectory())/lyra-debug.log")
        #expect(!expanded.contains("~"))
    }

    @Test("nil configured path derives the cache default from the given filename")
    func nilDerivesDefault() {
        #expect(
            FileDeveloperLog.resolvedPath(configured: nil, defaultFilename: "lyrics-debug.log")
                .hasSuffix("/lyra/lyrics-debug.log"))
    }

    @Test("blank configured path derives the cache default from the given filename")
    func blankDerivesDefault() {
        #expect(
            FileDeveloperLog.resolvedPath(configured: "   ", defaultFilename: "lyrics-debug.log")
                .hasSuffix("/lyra/lyrics-debug.log"))
    }

    @Test("the default filename is honored, so the sink stays purpose-agnostic")
    func defaultFilenameIsHonored() {
        #expect(
            FileDeveloperLog.resolvedPath(configured: nil, defaultFilename: "wallpaper-debug.log")
                .hasSuffix("/lyra/wallpaper-debug.log"))
    }

    @Test("an injected XDG_CACHE_HOME becomes the default base")
    func injectedCacheHomeIsUsed() {
        let path = FileDeveloperLog.resolvedPath(
            configured: nil, defaultFilename: "lyrics-debug.log", cacheHome: "/custom/cache")
        #expect(path == "/custom/cache/lyra/lyrics-debug.log")
    }

    @Test("a blank or nil XDG_CACHE_HOME falls back to ~/.cache")
    func blankOrNilCacheHomeFallsBack() {
        let fromBlank = FileDeveloperLog.resolvedPath(
            configured: nil, defaultFilename: "lyrics-debug.log", cacheHome: "   ")
        let fromNil = FileDeveloperLog.resolvedPath(
            configured: nil, defaultFilename: "lyrics-debug.log", cacheHome: nil)
        #expect(fromBlank == "\(NSHomeDirectory())/.cache/lyra/lyrics-debug.log")
        #expect(fromNil == "\(NSHomeDirectory())/.cache/lyra/lyrics-debug.log")
    }

    @Test("disabled log writes nothing")
    func disabledWritesNothing() {
        let path = Self.tempPath()
        FileDeveloperLog(enabled: false, path: path).record("should not appear")
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("enabled log creates the file and appends successive blocks")
    func enabledAppendsBlocks() throws {
        let path = Self.tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let log = FileDeveloperLog(enabled: true, path: path)
        log.record("block one")
        log.record("block two")
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        #expect(contents == "block one\nblock two\n")
    }

    @Test("a block that already ends in newline is not double-terminated")
    func trailingNewlineNotDuplicated() throws {
        let path = Self.tempPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let log = FileDeveloperLog(enabled: true, path: path)
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
