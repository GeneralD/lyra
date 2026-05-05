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

@MainActor
private func waitForTitleSuccess(_ presenter: HeaderPresenter, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while !presenter.titleState.isSuccess || !presenter.artistState.isSuccess,
        ContinuousClock.now < deadline
    {
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
                await waitForTitleSuccess(presenter)

                #expect(presenter.titleState == .success("Hello"))
                #expect(presenter.artistState == .success("World"))
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
                await waitForTitleSuccess(presenter)

                // Then send an idle (nil) update
                subject.send(TrackUpdate())
                // Wait for idle state
                let deadline = ContinuousClock.now + .seconds(3)
                while !presenter.titleState.isIdle, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }

                #expect(presenter.titleState.isIdle)
                #expect(presenter.artistState.isIdle)
                #expect(presenter.displayTitle == " ")
                #expect(presenter.displayArtist == " ")
                #expect(presenter.artworkData == nil)
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
                await waitForTitleSuccess(presenter)
                #expect(presenter.titleState == .success("Song"))

                presenter.stop()

                // After stop, new emissions should not change state
                subject.send(TrackUpdate(title: "New Song", artist: "New Artist"))
                try? await Task.sleep(for: .milliseconds(200))
                #expect(presenter.titleState == .success("Song"), "State should not change after stop")
            }
        }
    }
}
