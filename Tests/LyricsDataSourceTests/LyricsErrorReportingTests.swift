import Dependencies
import Domain
import Foundation
@preconcurrency import Papyrus
import Testing
import os

@testable import LyricsDataSource

/// #318 decided that LRCLIB's 404 is a *regular* "no lyrics for this track" answer and
/// must not be reported, so that "no lyrics" and "fetch is broken" stay distinguishable
/// in the daemon log. That was a non-obvious rule guarded by a bare `fputs`, which no
/// test could observe — a regression would have surfaced only as a daemon log filling
/// with 404s. Routing the report through an injected `ErrorLog` (#345) is what makes it
/// assertable, so these tests are the point of the refactor, not a side effect of it.
@Suite("LRCLIB error reporting (#318, #345)")
struct LyricsErrorReportingTests {
    @Test("a 404 is not reported — it is LRCLIB's regular no-lyrics answer")
    func notFoundIsSilent() async {
        let spy = ErrorLogSpy()

        _ = await dataSource(throwing: httpError(404), reportingTo: spy)
            .get(title: "Song", artist: "Artist", duration: nil)

        #expect(spy.reports.isEmpty)
    }

    @Test(
        "a server or transport failure IS reported — that is the case 404 must stay distinct from",
        arguments: [500, 502, 400, 429])
    func realFailuresAreReported(statusCode: Int) async {
        let spy = ErrorLogSpy()

        _ = await dataSource(throwing: httpError(statusCode), reportingTo: spy)
            .get(title: "Song", artist: "Artist", duration: nil)

        #expect(spy.reports.count == 1)
        #expect(spy.reports.first?.subsystem == .lrclib)
        #expect(spy.reports.first?.message.hasPrefix("get failed: ") == true)
    }

    @Test("an error carrying no HTTP response at all is reported — a timeout is not a 404")
    func responselessErrorIsReported() async {
        let spy = ErrorLogSpy()

        _ = await dataSource(throwing: StubError("connection lost"), reportingTo: spy)
            .get(title: "Song", artist: "Artist", duration: nil)

        #expect(spy.reports.count == 1)
        #expect(spy.reports.first?.subsystem == .lrclib)
    }

    // Both search indexes share the one guarded helper, so the rule has to hold on all
    // three entry points — and each has to name itself, or a report cannot be traced
    // back to the query that produced it.
    @Test("every entry point suppresses a 404")
    func allEntryPointsSuppressNotFound() async {
        let spy = ErrorLogSpy()
        let source = dataSource(throwing: httpError(404), reportingTo: spy)

        _ = await source.get(title: "Song", artist: "Artist", duration: nil)
        _ = await source.search(query: "Song Artist")
        _ = await source.search(trackName: "Song")

        #expect(spy.reports.isEmpty)
    }

    @Test("every entry point reports a real failure under its own operation name")
    func allEntryPointsNameThemselves() async {
        let spy = ErrorLogSpy()
        let source = dataSource(throwing: httpError(500), reportingTo: spy)

        _ = await source.get(title: "Song", artist: "Artist", duration: nil)
        _ = await source.search(query: "Song Artist")
        _ = await source.search(trackName: "Song")

        let operations = spy.reports.map { $0.message.components(separatedBy: " failed: ").first ?? "" }
        #expect(operations == ["get", "search(q)", "search(track_name)"])
        #expect(spy.reports.allSatisfy { $0.subsystem == .lrclib })
    }

    // MARK: - Helpers

    /// `@Dependency` captures the context at init, so the subject must be *built*
    /// inside the override — constructing it outside would keep the silent test sink.
    private func dataSource(throwing error: any Error, reportingTo spy: ErrorLogSpy) -> LyricsDataSourceImpl {
        withDependencies {
            $0.errorLog = spy
        } operation: {
            LyricsDataSourceImpl(
                api: LRCLibStub(
                    get: { _, _, _ in throw error },
                    search: { _ in throw error },
                    searchByTrackName: { _ in throw error }
                )
            )
        }
    }

    private func httpError(_ statusCode: Int) -> PapyrusError {
        PapyrusError(
            "Unsuccessful status code: \(statusCode).",
            nil,
            TestResponse(
                request: URLRequest(url: URL(string: "https://lrclib.net/api/get")!),
                statusCode: statusCode,
                body: Data()
            )
        )
    }
}

private struct Report: Sendable {
    let subsystem: ErrorSubsystem
    let message: String
}

/// A lock rather than an actor: `ErrorLog.record` is synchronous by contract, so the
/// call sites can report from anywhere without an await on the failure path.
private final class ErrorLogSpy: ErrorLog {
    private let state = OSAllocatedUnfairLock(initialState: [Report]())

    var reports: [Report] { state.withLock { $0 } }

    func record(_ subsystem: ErrorSubsystem, _ message: String) {
        state.withLock { $0.append(Report(subsystem: subsystem, message: message)) }
    }
}
