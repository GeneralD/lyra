import Domain
import Testing
import os

@testable import ErrorLog

@Suite("StandardErrorLog (#345)")
struct StandardErrorLogTests {
    @Test("default init() wires the live stderr printer")
    func defaultInitInstantiates() {
        // Exercising init() covers the production wiring; the real fputs is not
        // observable, which is exactly why the printer seam exists.
        _ = StandardErrorLog()
    }

    @Test("a report renders as one prefixed, subsystem-tagged, newline-terminated line")
    func rendersOneLine() {
        let sink = LineRecorder()

        StandardErrorLog(printer: { sink.append($0) }).record(.musicBrainz, "search failed: boom")

        #expect(sink.lines == ["lyra: MusicBrainz search failed: boom\n"])
    }

    // The point of the contract: the caller hands over the *message*, and the
    // prefix / subsystem / newline convention lives in one place instead of being
    // restated (and mis-stated) at each call site as it was before #345.
    @Test("every subsystem renders the same shape", arguments: ErrorSubsystem.allCases)
    func everySubsystemRendersTheSameShape(subsystem: ErrorSubsystem) {
        let sink = LineRecorder()

        StandardErrorLog(printer: { sink.append($0) }).record(subsystem, "op failed: x")

        #expect(sink.lines == ["lyra: \(subsystem.rawValue) op failed: x\n"])
    }

    // The naming rule as a test rather than a convention. Before #345 the subsystem
    // was a bare string per call site, and they had already drifted — `spectrum:`
    // carried a lowercase name and an extra colon that the other three did not.
    @Test("subsystem names are uniformly shaped", arguments: ErrorSubsystem.allCases)
    func subsystemNamesAreUniform(subsystem: ErrorSubsystem) {
        let name = subsystem.rawValue

        #expect(!name.isEmpty)
        #expect(name.first?.isUppercase == true)
        #expect(!name.contains(":"))
        #expect(!name.contains(" "))
    }

    @Test("each report is one call to the sink — nothing is buffered or merged")
    func reportsAreNotBatched() {
        let sink = LineRecorder()
        let log = StandardErrorLog(printer: { sink.append($0) })

        log.record(.lrclib, "get failed: a")
        log.record(.ai, "extraction failed: b")

        #expect(sink.lines == ["lyra: LRCLIB get failed: a\n", "lyra: AI extraction failed: b\n"])
    }
}

/// Collects what the sink printed. A lock rather than an actor because `record` is
/// synchronous — an actor could not be read from the nonisolated printer closure.
private final class LineRecorder: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [String]())

    var lines: [String] { state.withLock { $0 } }

    func append(_ line: String) {
        state.withLock { $0.append(line) }
    }
}
