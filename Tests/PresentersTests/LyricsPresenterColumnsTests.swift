@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

private struct StubTrackInteractor: TrackInteractor, @unchecked Sendable {
    var trackChangePublisher: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect = .init(duration: 0)
    var textLayout: TextLayout = .init(decodeEffect: .init(duration: 0))
    var artworkStyle: ArtworkStyle = .init()

    var trackChange: AnyPublisher<TrackUpdate, Never> { trackChangePublisher }
    var artwork: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { Empty().eraseToAnyPublisher() }
}

@MainActor
private func waitForLyricsSuccess(
    _ presenter: LyricsPresenter, timeout: Duration = .seconds(3)
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        switch presenter.lyricsState {
        case .success: return
        default: try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@Suite("LyricsPresenter columns")
struct LyricsPresenterColumnsTests {

    @MainActor
    @Test("columns returns empty when no lyrics")
    func emptyWhenNoLyrics() {
        withDependencies {
            $0.trackInteractor = StubTrackInteractor()
        } operation: {
            let presenter = LyricsPresenter()
            presenter.start()
            #expect(presenter.columns(in: CGSize(width: 600, height: 300), lineHeight: 30).columns.isEmpty)
        }
    }

    @MainActor
    @Test("columns splits plain lyrics into correct number of columns")
    func plainLyricsSplit() async {
        let subject = PassthroughSubject<TrackUpdate, Never>()
        let lines = (1...25).map { "Line \($0)" }
        let content = LyricsContent.plain(lines)

        await withDependencies {
            $0.trackInteractor = StubTrackInteractor(
                trackChangePublisher: subject.eraseToAnyPublisher(),
                textLayout: TextLayout(decodeEffect: .init(duration: 0))
            )
        } operation: {
            let presenter = LyricsPresenter()
            presenter.start()

            subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
            await waitForLyricsSuccess(presenter)

            let cols = presenter.columns(in: CGSize(width: 600, height: 300), lineHeight: 30).columns
            #expect(cols.count == 3, "25 lines / 10 per column = 3 columns")
            #expect(cols[0].entries.count == 10)
            #expect(cols[1].entries.count == 10)
            #expect(cols[2].entries.count == 5)
        }
    }

    @MainActor
    @Test("columns respects maxColumns limit")
    func maxColumnsLimit() async {
        let subject = PassthroughSubject<TrackUpdate, Never>()
        let lines = (1...100).map { "Line \($0)" }
        let content = LyricsContent.plain(lines)

        await withDependencies {
            $0.trackInteractor = StubTrackInteractor(
                trackChangePublisher: subject.eraseToAnyPublisher(),
                textLayout: TextLayout(decodeEffect: .init(duration: 0))
            )
        } operation: {
            let presenter = LyricsPresenter()
            presenter.start()

            subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
            await waitForLyricsSuccess(presenter)

            let cols = presenter.columns(in: CGSize(width: 600, height: 300), lineHeight: 30).columns
            #expect(cols.count == 3, "Should cap at maxColumns")
        }
    }

    @MainActor
    @Test("timed lyrics columns have highlightIndex from activeLineIndex")
    func timedHighlightIndex() async {
        let subject = PassthroughSubject<TrackUpdate, Never>()
        let timedLines = [
            LyricLine(time: 0.0, text: "First"),
            LyricLine(time: 5.0, text: "Second"),
        ]
        let content = LyricsContent.timed(timedLines)

        await withDependencies {
            $0.trackInteractor = StubTrackInteractor(
                trackChangePublisher: subject.eraseToAnyPublisher(),
                textLayout: TextLayout(decodeEffect: .init(duration: 0))
            )
        } operation: {
            let presenter = LyricsPresenter()
            presenter.start()

            subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
            await waitForLyricsSuccess(presenter)

            let cols = presenter.columns(in: CGSize(width: 600, height: 300), lineHeight: 30).columns
            // activeLineIndex is nil initially for timed lyrics
            #expect(cols.first?.highlightIndex == nil)
        }
    }

    @MainActor
    @Test("plain lyrics columns have nil highlightIndex")
    func plainNoHighlight() async {
        let subject = PassthroughSubject<TrackUpdate, Never>()
        let content = LyricsContent.plain(["A", "B"])

        await withDependencies {
            $0.trackInteractor = StubTrackInteractor(
                trackChangePublisher: subject.eraseToAnyPublisher(),
                textLayout: TextLayout(decodeEffect: .init(duration: 0))
            )
        } operation: {
            let presenter = LyricsPresenter()
            presenter.start()

            subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
            await waitForLyricsSuccess(presenter)

            let cols = presenter.columns(in: CGSize(width: 600, height: 300), lineHeight: 30).columns
            #expect(cols.first?.highlightIndex == nil)
        }
    }
}
