@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Stub

private struct StubTrackInteractor: TrackInteractor, @unchecked Sendable {
    var trackChangePublisher: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher()
    var artworkPublisher: AnyPublisher<Data?, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect = .init(duration: 0)
    var textLayout: TextLayout = .init()
    var artworkStyle: ArtworkStyle = .init()

    var trackChange: AnyPublisher<TrackUpdate, Never> { trackChangePublisher }
    var artwork: AnyPublisher<Data?, Never> { artworkPublisher }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { Empty().eraseToAnyPublisher() }
}

// MARK: - Helpers

@MainActor
private func waitForTitleSuccess(_ presenter: HeaderPresenter, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while !presenter.titleState.isSuccess || !presenter.artistState.isSuccess,
        ContinuousClock.now < deadline
    {
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

@Suite("HeaderPresenter duplicate / artwork interactions")
struct HeaderPresenterDuplicateTests {

    @Suite("duplicate track suppression")
    struct DuplicateTrack {
        @MainActor
        @Test("sending same title twice does not re-trigger decode effect")
        func sameTitleTwiceStaysSuccess() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let update = TrackUpdate(title: "Same", artist: "Artist")

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher(),
                    decodeEffectConfig: .init(duration: 0)
                )
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                // First send
                subject.send(update)
                await waitForTitleSuccess(presenter)
                #expect(presenter.titleState == .success("Same"))
                #expect(presenter.artistState == .success("Artist"))

                // Second send with identical title/artist
                subject.send(update)
                try? await Task.sleep(for: .milliseconds(200))

                // Should remain .success, not reset to .revealing
                #expect(presenter.titleState == .success("Same"))
                #expect(presenter.artistState == .success("Artist"))
            }
        }
    }

    @Suite("artwork stream")
    struct ArtworkStream {
        @MainActor
        @Test("artwork updates without affecting titleState")
        func artworkUpdatesIndependently() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let artworkSubject = PassthroughSubject<Data?, Never>()
            let update = TrackUpdate(title: "Song", artist: "Band")

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: trackSubject.eraseToAnyPublisher(),
                    artworkPublisher: artworkSubject.eraseToAnyPublisher(),
                    decodeEffectConfig: .init(duration: 0)
                )
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                // Set up title first
                trackSubject.send(update)
                await waitForTitleSuccess(presenter)
                #expect(presenter.titleState == .success("Song"))
                #expect(presenter.artworkData == nil)

                // Send artwork
                let imageData = Data([0xFF, 0xD8, 0xFF])
                artworkSubject.send(imageData)
                try? await Task.sleep(for: .milliseconds(200))

                #expect(presenter.artworkData == imageData)
                // Title state must remain unchanged
                #expect(presenter.titleState == .success("Song"))
                #expect(presenter.artistState == .success("Band"))
            }
        }

        @MainActor
        @Test("changing artwork while title is animating does not affect title animation")
        func artworkChangesDuringTitleAnimation() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let artworkSubject = PassthroughSubject<Data?, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: trackSubject.eraseToAnyPublisher(),
                    artworkPublisher: artworkSubject.eraseToAnyPublisher(),
                    decodeEffectConfig: .init(duration: 0)
                )
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                // Send track and artwork nearly simultaneously
                trackSubject.send(TrackUpdate(title: "New Song", artist: "New Artist"))
                let artData = Data([0x89, 0x50, 0x4E, 0x47])
                artworkSubject.send(artData)
                await waitForTitleSuccess(presenter)

                // Both should have settled correctly
                #expect(presenter.artworkData == artData)
                #expect(presenter.titleState == .success("New Song"))
                #expect(presenter.artistState == .success("New Artist"))

                // Now change artwork again
                let newArtData = Data([0x00, 0x01])
                artworkSubject.send(newArtData)
                try? await Task.sleep(for: .milliseconds(200))

                #expect(presenter.artworkData == newArtData)
                // Title state still untouched
                #expect(presenter.titleState == .success("New Song"))
            }
        }
    }
}
