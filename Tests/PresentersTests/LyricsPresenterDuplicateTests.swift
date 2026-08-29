@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import TestSupport
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

extension FetchState {
    fileprivate var isSuccess: Bool {
        switch self {
        case .success: true
        default: false
        }
    }
}

// MARK: - Tests

@Suite("LyricsPresenter duplicate / playback interactions", .timeLimit(.minutes(1)))
struct LyricsPresenterDuplicateTests {

    @Suite("duplicate lyrics suppression", .timeLimit(.minutes(1)))
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
                await settle(presenter.$lyricsState) { $0.isSuccess }
                #expect(presenter.lyricsState == .success(content))

                // Track state transitions after the duplicate send.
                let transitions = Collector<FetchState<LyricsContent>>()
                let cancellable = presenter.$lyricsState.dropFirst().sink { transitions.append($0) }

                // Second send with identical content — guarded, must not
                // reset to .revealing.
                subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))

                // Sentinel: a distinct lyrics update through the same
                // trackChange pipeline. Both sends are delivered by the same
                // `.receive(on: .main)` sink in order, so once the sentinel's
                // own `.success` lands, the duplicate above has already been
                // fully (non-)processed.
                let sentinelContent = LyricsContent.plain(["Sentinel"])
                subject.send(TrackUpdate(lyrics: sentinelContent, lyricsState: .resolved))
                await settle(presenter.$lyricsState) { $0 == .success(sentinelContent) }

                #expect(transitions.values == [.revealing(sentinelContent), .success(sentinelContent)])
                #expect(presenter.displayLyricLines.count == 1)
                _ = cancellable
            }
        }
    }

    @Suite("playback position", .timeLimit(.minutes(1)))
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
                await settle(presenter.$lyricsState) { $0.isSuccess }
                #expect(presenter.lyricsState == .success(content))

                // Send playback position at 6 seconds (should highlight "Second")
                positionSubject.send(PlaybackPosition(rawElapsed: 6.0, playbackRate: 1.0))
                #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 1 })
                #expect(presenter.activeLineIndex == 1)

                // lyricsState must remain .success
                #expect(presenter.lyricsState == .success(content))

                // Advance to 11 seconds (should highlight "Third")
                positionSubject.send(PlaybackPosition(rawElapsed: 11.0, playbackRate: 1.0))
                #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 2 })
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
                await settle(presenter.$lyricsState) { $0.isSuccess }

                // Set position while playing
                positionSubject.send(PlaybackPosition(rawElapsed: 6.0, playbackRate: 1.0))
                #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 1 })
                #expect(presenter.activeLineIndex == 1)

                // Pause (rate = 0), send new position — paused guard should keep index at 1.
                // Negative tick window: tick a bounded number of times and assert the
                // index never changes away from 1 (#349).
                positionSubject.send(PlaybackPosition(rawElapsed: 6.0, playbackRate: 0))
                #expect(
                    await tickUntil(100, tick: presenter.updateActiveLineTick) {
                        presenter.activeLineIndex != 1
                    } == false)
                #expect(presenter.activeLineIndex == 1)
            }
        }
    }
}
