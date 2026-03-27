@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Stub

private struct StubTrackInteractor: TrackInteractor, @unchecked Sendable {
    var trackChangePublisher: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher()
    var playbackPositionPublisher: AnyPublisher<PlaybackPosition, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect = .init(duration: 0)
    var textLayout: TextLayout = .init(decodeEffect: .init(duration: 0))
    var artworkStyle: ArtworkStyle = .init()

    var trackChange: AnyPublisher<TrackUpdate, Never> { trackChangePublisher }
    var artwork: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { playbackPositionPublisher }
}

// MARK: - Helpers

@MainActor
private func waitForLyricsSuccess(_ presenter: LyricsPresenter, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while !presenter.lyricsState.isSuccess, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

extension FetchState {
    fileprivate var isSuccess: Bool {
        switch self {
        case .success: true
        default: false
        }
    }
}

// MARK: - Tests

@Suite("LyricsPresenter duplicate / playback interactions")
struct LyricsPresenterDuplicateTests {

    @Suite("duplicate lyrics suppression")
    struct DuplicateLyrics {
        @MainActor
        @Test("sending same lyrics content twice does not re-trigger reveal")
        func sameLyricsTwiceStaysSuccess() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let content = LyricsContent.plain(["Line A", "Line B"])

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher(),
                    textLayout: TextLayout(decodeEffect: .init(duration: 0))
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                // First send
                subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
                await waitForLyricsSuccess(presenter)
                #expect(presenter.lyricsState == .success(content))

                // Second send with identical content
                subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
                try? await Task.sleep(for: .milliseconds(200))

                // Should remain .success, not reset to .revealing
                #expect(presenter.lyricsState == .success(content))
                #expect(presenter.displayLyricLines.count == 2)
            }
        }
    }

    @Suite("playback position")
    struct PlaybackPositionUpdates {
        @MainActor
        @Test("playbackPosition updates activeLineIndex via updateActiveLineTick without changing lyricsState")
        func playbackPositionUpdatesActiveIndex() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let positionSubject = PassthroughSubject<PlaybackPosition, Never>()
            let timedLines: [LyricLine] = [
                LyricLine(time: 0.0, text: "First"),
                LyricLine(time: 5.0, text: "Second"),
                LyricLine(time: 10.0, text: "Third"),
            ]
            let content = LyricsContent.timed(timedLines)

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: trackSubject.eraseToAnyPublisher(),
                    playbackPositionPublisher: positionSubject.eraseToAnyPublisher(),
                    textLayout: TextLayout(decodeEffect: .init(duration: 0))
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                // First, resolve lyrics
                trackSubject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
                await waitForLyricsSuccess(presenter)
                #expect(presenter.lyricsState == .success(content))

                // Send playback position at 6 seconds (should highlight "Second")
                positionSubject.send(PlaybackPosition(elapsed: 6.0, playbackRate: 1.0))
                var deadline = ContinuousClock.now + .seconds(3)
                while ContinuousClock.now < deadline {
                    presenter.updateActiveLineTick()
                    if presenter.activeLineIndex == 1 { break }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                #expect(presenter.activeLineIndex == 1)

                // lyricsState must remain .success
                #expect(presenter.lyricsState == .success(content))

                // Advance to 11 seconds (should highlight "Third")
                positionSubject.send(PlaybackPosition(elapsed: 11.0, playbackRate: 1.0))
                deadline = ContinuousClock.now + .seconds(3)
                while ContinuousClock.now < deadline {
                    presenter.updateActiveLineTick()
                    if presenter.activeLineIndex == 2 { break }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                #expect(presenter.activeLineIndex == 2)
                #expect(presenter.lyricsState == .success(content))
            }
        }

        @MainActor
        @Test("paused playback (rate 0) does not update activeLineIndex")
        func pausedPlaybackKeepsIndex() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let positionSubject = PassthroughSubject<PlaybackPosition, Never>()
            let timedLines: [LyricLine] = [
                LyricLine(time: 0.0, text: "First"),
                LyricLine(time: 5.0, text: "Second"),
            ]
            let content = LyricsContent.timed(timedLines)

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: trackSubject.eraseToAnyPublisher(),
                    playbackPositionPublisher: positionSubject.eraseToAnyPublisher(),
                    textLayout: TextLayout(decodeEffect: .init(duration: 0))
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                trackSubject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
                await waitForLyricsSuccess(presenter)

                // Set position while playing
                positionSubject.send(PlaybackPosition(elapsed: 6.0, playbackRate: 1.0))
                try? await Task.sleep(for: .milliseconds(200))
                presenter.updateActiveLineTick()
                #expect(presenter.activeLineIndex == 1)

                // Pause (rate = 0), send new position
                positionSubject.send(PlaybackPosition(elapsed: 6.0, playbackRate: 0))
                try? await Task.sleep(for: .milliseconds(200))
                presenter.updateActiveLineTick()

                // activeLineIndex should not update when paused
                #expect(presenter.activeLineIndex == 1)
            }
        }
    }
}
