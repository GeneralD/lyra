@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Stub

private struct StubTrackInteractor: TrackInteractor, @unchecked Sendable {
    var trackChangePublisher: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect = .init(duration: 0)
    var textLayout: TextLayout = .init()
    var artworkStyle: ArtworkStyle = .init()

    var trackChange: AnyPublisher<TrackUpdate, Never> { trackChangePublisher }
    var artwork: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { Empty().eraseToAnyPublisher() }
    var audioSource: AnyPublisher<AudioSourceState, Never> { Empty().eraseToAnyPublisher() }
}

// MARK: - Helpers

@MainActor
private func waitForReveal(_ presenter: HeaderPresenter, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while presenter.titlePhase != .revealed || presenter.artistPhase != .revealed,
        ContinuousClock.now < deadline
    {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - Tests

@Suite("HeaderPresenter")
struct HeaderPresenterTests {

    @Suite("start")
    struct Start {
        @MainActor
        @Test("loads titleStyle and artistStyle from interactor")
        func loadsTitleAndArtistStyle() {
            let customTitle = TextAppearance(fontSize: 24, fontWeight: "heavy")
            let customArtist = TextAppearance(fontSize: 14, fontWeight: "light")
            let layout = TextLayout(title: customTitle, artist: customArtist)

            withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    decodeEffectConfig: .init(duration: 0),
                    textLayout: layout
                )
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                #expect(presenter.titleStyle.fontSize == 24)
                #expect(presenter.titleStyle.fontWeight == "heavy")
                #expect(presenter.artistStyle.fontSize == 14)
                #expect(presenter.artistStyle.fontWeight == "light")
            }
        }

        @MainActor
        @Test("loads artworkSize and artworkOpacity from interactor")
        func loadsArtworkStyle() {
            let artwork = ArtworkStyle(size: 128, opacity: 0.5)

            withDependencies {
                $0.trackInteractor = StubTrackInteractor(artworkStyle: artwork)
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                #expect(presenter.artworkSize == 128)
                #expect(presenter.artworkOpacity == 0.5)
            }
        }
    }

    @Suite("receive TrackUpdate")
    struct Receive {
        @MainActor
        @Test("receiving a track update sets displayTitle via decode effect")
        func receivesTrackUpdateTitle() async throws {
            let update = TrackUpdate(title: "Hello", artist: "World")
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher(),
                    decodeEffectConfig: .init(duration: 0)
                )
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                subject.send(update)
                await waitForReveal(presenter)

                #expect(presenter.displayTitle == "Hello")
                #expect(presenter.displayArtist == "World")
                #expect(presenter.titlePhase == .revealed)
                #expect(presenter.artistPhase == .revealed)
            }
        }

        @MainActor
        @Test("receiving idle update resets state")
        func receivesIdleUpdate() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher(),
                    decodeEffectConfig: .init(duration: 0)
                )
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                // First send a valid track and wait for decode to complete
                subject.send(TrackUpdate(title: "Song", artist: "Artist"))
                await waitForReveal(presenter)

                // Then send an idle (nil) update
                subject.send(TrackUpdate())
                // Wait for idle state
                let deadline = ContinuousClock.now + .seconds(3)
                while presenter.titlePhase != .idle, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }

                #expect(presenter.titlePhase == .idle)
                #expect(presenter.artistPhase == .idle)
                #expect(presenter.displayTitle == " ")
                #expect(presenter.displayArtist == " ")
                #expect(presenter.artworkImage == nil)
            }
        }
    }

    @Suite("AI processing indicator")
    struct AIProcessing {
        private static let processing: ColorStyle = .solid("#FF00FF")
        private static let titleColor: ColorStyle = .solid("#112233")
        private static let artistColor: ColorStyle = .solid("#445566")

        private static func makeStub(_ subject: PassthroughSubject<TrackUpdate, Never>) -> StubTrackInteractor {
            StubTrackInteractor(
                trackChangePublisher: subject.eraseToAnyPublisher(),
                decodeEffectConfig: .init(duration: 0, processingColor: processing),
                textLayout: TextLayout(
                    title: TextAppearance(color: titleColor),
                    artist: TextAppearance(color: artistColor)
                )
            )
        }

        @MainActor
        @Test("aiResolving update scrambles both fields in processingColor without settling")
        func processingState() async {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            // An injected TestClock drives the indefinite scramble loop deterministically:
            // the synchronous first frame renders immediately, then advancing the clock
            // runs further frames without any real-time wait.
            let clock = TestClock()

            await withDependencies {
                $0.trackInteractor = Self.makeStub(subject)
                $0.continuousClock = clock
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                subject.send(
                    TrackUpdate(title: "Song", artist: "Artist", lyricsState: .loading, aiResolving: true))
                await waitUntil { presenter.titleColor == Self.processing }

                #expect(presenter.titleColor == Self.processing)
                #expect(presenter.artistColor == Self.processing)
                #expect(presenter.titlePhase == .revealing)
                #expect(presenter.artistPhase == .revealing)
                #expect(presenter.displayTitle != " ")
                #expect(presenter.displayArtist != " ")

                // Sustained: advancing the clock through several scramble frames must keep
                // the loop scrambling in the processing color — it never auto-settles.
                await clock.advance(by: .milliseconds(300))
                #expect(presenter.titlePhase == .revealing)
                #expect(presenter.titleColor == Self.processing)

                presenter.stop()
            }
        }

        @MainActor
        @Test("resolved update after processing settles to the normal color and final text")
        func settlesAfterProcessing() async {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = Self.makeStub(subject)
                $0.continuousClock = TestClock()
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                subject.send(
                    TrackUpdate(title: "Song", artist: "Artist", lyricsState: .loading, aiResolving: true))
                await waitUntil { presenter.titleColor == Self.processing }

                subject.send(TrackUpdate(title: "AI Song", artist: "AI Artist", lyricsState: .resolved))
                await waitForReveal(presenter)

                #expect(presenter.displayTitle == "AI Song")
                #expect(presenter.displayArtist == "AI Artist")
                #expect(presenter.titleColor == Self.titleColor)
                #expect(presenter.artistColor == Self.artistColor)
                #expect(presenter.titlePhase == .revealed)
                #expect(presenter.artistPhase == .revealed)
            }
        }

        @MainActor
        @Test("non-AI update reveals in the normal color, never the processing color")
        func normalUpdateUsesNormalColor() async {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = Self.makeStub(subject)
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                subject.send(TrackUpdate(title: "Song", artist: "Artist", lyricsState: .resolved))
                await waitForReveal(presenter)

                #expect(presenter.titleColor == Self.titleColor)
                #expect(presenter.artistColor == Self.artistColor)
                #expect(presenter.titleColor != Self.processing)
            }
        }
    }

    @Suite("stop")
    struct Stop {
        @MainActor
        @Test("stop cancels subscriptions and effects")
        func stopCancels() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher(),
                    decodeEffectConfig: .init(duration: 0)
                )
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                subject.send(TrackUpdate(title: "Song", artist: "Artist"))
                await waitForReveal(presenter)
                #expect(presenter.displayTitle == "Song")

                presenter.stop()

                // After stop, new emissions should not change state
                subject.send(TrackUpdate(title: "New Song", artist: "New Artist"))
                try? await Task.sleep(for: .milliseconds(200))
                #expect(presenter.displayTitle == "Song", "Display should not change after stop")
                #expect(presenter.titlePhase == .revealed, "Phase should not change after stop")
            }
        }
    }
}
