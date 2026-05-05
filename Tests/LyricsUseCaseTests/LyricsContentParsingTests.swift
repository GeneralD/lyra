import Domain
import Foundation
import Testing

@testable import LyricsUseCase

@Suite("LyricsUseCaseImpl.parseLyricsContent")
struct LyricsContentParsingTests {
    // MARK: - From LyricsResult

    @Suite("from LyricsResult")
    struct FromResult {
        private let parser = LyricsUseCaseImpl()

        @Test("nil result returns nil")
        func nilResult() {
            #expect(parser.parseLyricsContent(from: nil) == nil)
        }

        @Test("result with no lyrics returns nil")
        func noLyrics() {
            let result = LyricsResult(plainLyrics: nil, syncedLyrics: nil)
            #expect(parser.parseLyricsContent(from: result) == nil)
        }

        @Test("plain lyrics splits by newline")
        func plainLyrics() {
            let result = LyricsResult(plainLyrics: "Line 1\nLine 2\nLine 3")
            guard case .plain(let lines) = parser.parseLyricsContent(from: result) else {
                Issue.record("Expected .plain")
                return
            }
            #expect(lines == ["Line 1", "Line 2", "Line 3"])
        }

        @Test("synced lyrics preferred over plain when both present")
        func syncedPreferred() {
            let result = LyricsResult(
                plainLyrics: "Plain text",
                syncedLyrics: "[00:01.00] Synced line"
            )
            guard case .timed = parser.parseLyricsContent(from: result) else {
                Issue.record("Expected .timed")
                return
            }
        }
    }

    // MARK: - Synced Lyrics Parsing

    @Suite("synced lyrics parsing")
    struct SyncedParsing {
        private let parser = LyricsUseCaseImpl()

        @Test("parses standard LRC format [mm:ss.xx]")
        func standardLRC() {
            let result = LyricsResult(syncedLyrics: "[01:23.45] Hello world")
            guard case .timed(let lines) = parser.parseLyricsContent(from: result) else {
                Issue.record("Expected .timed")
                return
            }
            #expect(lines.count == 1)
            #expect(lines[0].time == 83.45)
            #expect(lines[0].text == "Hello world")
        }

        @Test("parses multiple lines")
        func multipleLines() {
            let synced = """
                [00:00.00] First line
                [00:05.50] Second line
                [01:00.00] Third line
                """
            let result = LyricsResult(syncedLyrics: synced)
            guard case .timed(let lines) = parser.parseLyricsContent(from: result) else {
                Issue.record("Expected .timed")
                return
            }
            #expect(lines.count == 3)
            #expect(lines[0].time == 0.0)
            #expect(lines[1].time == 5.5)
            #expect(lines[2].time == 60.0)
        }

        @Test("parses integer seconds without decimal")
        func integerSeconds() {
            let result = LyricsResult(syncedLyrics: "[02:30] No decimal")
            guard case .timed(let lines) = parser.parseLyricsContent(from: result) else {
                Issue.record("Expected .timed")
                return
            }
            #expect(lines[0].time == 150.0)
            #expect(lines[0].text == "No decimal")
        }

        @Test("skips malformed lines")
        func malformedLines() {
            let synced = """
                [00:01.00] Good line
                This is not LRC
                [bad] Also bad
                [00:02.00] Another good line
                """
            let result = LyricsResult(syncedLyrics: synced)
            guard case .timed(let lines) = parser.parseLyricsContent(from: result) else {
                Issue.record("Expected .timed")
                return
            }
            #expect(lines.count == 2)
        }

        @Test("empty synced string falls back to plain")
        func emptySynced() {
            let result = LyricsResult(plainLyrics: "Fallback", syncedLyrics: "")
            guard case .plain(let lines) = parser.parseLyricsContent(from: result) else {
                Issue.record("Expected .plain")
                return
            }
            #expect(lines == ["Fallback"])
        }

        @Test("synced with only malformed lines falls back to plain")
        func allMalformed() {
            let result = LyricsResult(plainLyrics: "Fallback", syncedLyrics: "no timestamps here")
            guard case .plain(let lines) = parser.parseLyricsContent(from: result) else {
                Issue.record("Expected .plain")
                return
            }
            #expect(lines == ["Fallback"])
        }

        @Test("trims whitespace from line text")
        func trimWhitespace() {
            let result = LyricsResult(syncedLyrics: "[00:01.00]   Padded text   ")
            guard case .timed(let lines) = parser.parseLyricsContent(from: result) else {
                Issue.record("Expected .timed")
                return
            }
            #expect(lines[0].text == "Padded text")
        }
    }
}
