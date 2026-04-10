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
    var textLayout: TextLayout = .init()
    var artworkStyle: ArtworkStyle = .init()

    var trackChange: AnyPublisher<TrackUpdate, Never> { trackChangePublisher }
    var artwork: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { playbackPositionPublisher }
}

// MARK: - Helpers

@MainActor
private func waitForLyricsSuccess(_ presenter: LyricsPresenter, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        switch presenter.lyricsState {
        case .success: return
        default: try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

// MARK: - Tests

@Suite("LyricsPresenter")
struct LyricsPresenterTests {

    @Suite("start")
    struct Start {
        @MainActor
        @Test("loads lyricStyle and highlightStyle from interactor")
        func loadsStyles() {
            let customLyric = TextAppearance(fontSize: 16, fontWeight: "bold")
            let customHighlight = TextAppearance(fontSize: 16, color: .solid("#FFD700"))
            let layout = TextLayout(lyric: customLyric, highlight: customHighlight)

            withDependencies {
                $0.trackInteractor = StubTrackInteractor(textLayout: layout)
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                #expect(presenter.lyricStyle.fontSize == 16)
                #expect(presenter.lyricStyle.fontWeight == "bold")
                #expect(presenter.highlightStyle.color == .solid("#FFD700"))
            }
        }
    }

    @Suite("receive TrackUpdate")
    struct Receive {
        @MainActor
        @Test("loading state sets lyricsState to .loading")
        func loadingState() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher()
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                subject.send(TrackUpdate(lyricsState: .loading))
                let deadline = ContinuousClock.now + .seconds(3)
                while !presenter.lyricsState.isLoading, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }

                #expect(presenter.lyricsState.isLoading)
            }
        }

        @MainActor
        @Test("notFound sets lyricsState to .failure")
        func notFoundState() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher()
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                subject.send(TrackUpdate(lyricsState: .notFound))
                let deadline = ContinuousClock.now + .seconds(3)
                while presenter.lyricsState != .failure, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }

                #expect(presenter.lyricsState == .failure)
                #expect(presenter.displayLyricLines.isEmpty)
            }
        }

        @MainActor
        @Test("idle resets lyricsState")
        func idleState() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher()
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                // First set to loading
                subject.send(TrackUpdate(lyricsState: .loading))
                var deadline = ContinuousClock.now + .seconds(3)
                while !presenter.lyricsState.isLoading, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }

                // Then idle
                subject.send(TrackUpdate(lyricsState: .idle))
                deadline = ContinuousClock.now + .seconds(3)
                while !presenter.lyricsState.isIdle, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }

                #expect(presenter.lyricsState.isIdle)
                #expect(presenter.displayLyricLines.isEmpty)
                #expect(presenter.activeLineIndex == nil)
            }
        }

        @MainActor
        @Test("resolved lyrics triggers reveal")
        func resolvedLyrics() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let content = LyricsContent.plain(["Line 1", "Line 2"])

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

                #expect(presenter.lyricsState == .success(content))
                #expect(presenter.displayLyricLines.count == 2)
            }
        }
    }

    @Suite("updateActiveLineTick")
    struct UpdateActiveLineTick {
        @MainActor
        @Test("skips update when playback rate is 0 (paused)")
        func skipsWhenPaused() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let positionSubject = PassthroughSubject<PlaybackPosition, Never>()
            let lines: [LyricLine] = [
                .init(time: 0, text: "Line A"),
                .init(time: 5, text: "Line B"),
            ]
            let content = LyricsContent.timed(lines)

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

                // Send a paused playback position (rate = 0)
                positionSubject.send(PlaybackPosition(elapsed: 6, playbackRate: 0))
                // Allow Combine to deliver the position update
                try? await Task.sleep(for: .milliseconds(50))

                presenter.updateActiveLineTick()
                // activeLineIndex should remain nil because playback is paused
                #expect(presenter.activeLineIndex == nil)
            }
        }

        @MainActor
        @Test("updates active line index for timed lyrics")
        func updatesActiveLineForTimedLyrics() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let positionSubject = PassthroughSubject<PlaybackPosition, Never>()
            let lines: [LyricLine] = [
                .init(time: 0, text: "Line A"),
                .init(time: 5, text: "Line B"),
                .init(time: 10, text: "Line C"),
            ]
            let content = LyricsContent.timed(lines)

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

                // Send position at 6s — should highlight Line B (time=5)
                positionSubject.send(PlaybackPosition(elapsed: 6, playbackRate: 1.0))
                // Allow Combine to deliver the position update
                try? await Task.sleep(for: .milliseconds(50))

                presenter.updateActiveLineTick()
                #expect(presenter.activeLineIndex == 1)
            }
        }
    }

    @Suite("receive edge cases")
    struct ReceiveEdgeCases {
        @MainActor
        @Test("resolved with nil lyrics is ignored")
        func resolvedNilLyrics() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher(),
                    textLayout: TextLayout(decodeEffect: .init(duration: 0))
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                // Send resolved with nil lyrics — should be guarded
                subject.send(TrackUpdate(lyrics: nil, lyricsState: .resolved))
                try? await Task.sleep(for: .milliseconds(200))

                // State should not have changed from idle
                #expect(presenter.lyricsState.isIdle)
            }
        }

        @MainActor
        @Test("resolved with same lyrics does not re-reveal")
        func resolvedDuplicateLyrics() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let content = LyricsContent.plain(["Same line"])

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher(),
                    textLayout: TextLayout(decodeEffect: .init(duration: 0))
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                // First reveal
                subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
                await waitForLyricsSuccess(presenter)
                #expect(presenter.lyricsState == .success(content))

                // Track state transitions after duplicate send
                var enteredRevealing = false
                let cancellable = presenter.$lyricsState.dropFirst().sink { state in
                    if state.isRevealing { enteredRevealing = true }
                }

                // Send same lyrics again — guard prevents re-reveal
                subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
                try? await Task.sleep(for: .milliseconds(100))
                #expect(presenter.lyricsState == .success(content))
                #expect(!enteredRevealing, "should not re-enter .revealing for duplicate lyrics")
                _ = cancellable
            }
        }
    }

    @Suite("stop")
    struct Stop {
        @MainActor
        @Test("stop cancels subscriptions and effects")
        func stopCancels() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let content = LyricsContent.plain(["Line 1"])

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
                #expect(presenter.lyricsState == .success(content))

                presenter.stop()

                // After stop, new emissions should not change state
                let newContent = LyricsContent.plain(["New Line"])
                subject.send(TrackUpdate(lyrics: newContent, lyricsState: .resolved))
                try? await Task.sleep(for: .milliseconds(200))
                #expect(
                    presenter.lyricsState == .success(content),
                    "State should not change after stop")
            }
        }
    }
}
