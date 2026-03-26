@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presentation

// MARK: - Stub

private struct StubTrackInteractor: TrackInteractor, @unchecked Sendable {
    var trackChangePublisher: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect = .init(duration: 0)
    var textLayout: TextLayout = .init()
    var artworkStyle: ArtworkStyle = .init()

    var trackChange: AnyPublisher<TrackUpdate, Never> { trackChangePublisher }
    var artwork: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { Empty().eraseToAnyPublisher() }
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
                try? await Task.sleep(for: .milliseconds(100))

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
                try? await Task.sleep(for: .milliseconds(100))

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
                try? await Task.sleep(for: .milliseconds(100))

                // Then idle
                subject.send(TrackUpdate(lyricsState: .idle))
                try? await Task.sleep(for: .milliseconds(100))

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
                try? await Task.sleep(for: .milliseconds(200))

                // With duration 0, decode should complete to success
                #expect(presenter.lyricsState == .success(content))
                #expect(presenter.displayLyricLines.count == 2)
            }
        }
    }
}
