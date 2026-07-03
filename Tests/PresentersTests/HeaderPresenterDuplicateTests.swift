import AppKit
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
private func waitForReveal(_ presenter: HeaderPresenter, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while presenter.titlePhase != .revealed || presenter.artistPhase != .revealed,
        ContinuousClock.now < deadline
    {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func fixtureArtworkData(color: NSColor = .red) throws -> Data {
    let image = NSImage(size: NSSize(width: 1, height: 1))
    image.lockFocus()
    color.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
    image.unlockFocus()
    return try #require(image.tiffRepresentation)
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
                await waitForReveal(presenter)
                #expect(presenter.displayTitle == "Same")
                #expect(presenter.displayArtist == "Artist")

                // Second send with identical title/artist
                subject.send(update)
                try? await Task.sleep(for: .milliseconds(200))

                // Should remain revealed, not reset to .revealing
                #expect(presenter.titlePhase == .revealed)
                #expect(presenter.artistPhase == .revealed)
                #expect(presenter.displayTitle == "Same")
                #expect(presenter.displayArtist == "Artist")
            }
        }
    }

    @Suite("artwork stream")
    struct ArtworkStream {
        @MainActor
        @Test("artwork updates without affecting title display")
        func artworkUpdatesIndependently() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let artworkSubject = PassthroughSubject<Data?, Never>()
            let update = TrackUpdate(title: "Song", artist: "Band")

            try await withDependencies {
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
                await waitForReveal(presenter)
                #expect(presenter.displayTitle == "Song")
                #expect(presenter.artworkImage == nil)

                // Send artwork
                let imageData = try fixtureArtworkData()
                artworkSubject.send(imageData)
                let artDeadline = ContinuousClock.now + .seconds(3)
                while presenter.artworkImage == nil, ContinuousClock.now < artDeadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }

                let cachedImage = try #require(presenter.artworkImage)
                // Title display must remain unchanged
                #expect(presenter.displayTitle == "Song")
                #expect(presenter.displayArtist == "Band")

                artworkSubject.send(imageData)
                try? await Task.sleep(for: .milliseconds(200))

                #expect(presenter.artworkImage === cachedImage)
            }
        }

        @MainActor
        @Test("changing artwork while title is animating does not affect title animation")
        func artworkChangesDuringTitleAnimation() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let artworkSubject = PassthroughSubject<Data?, Never>()

            try await withDependencies {
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
                let artData = try fixtureArtworkData()
                artworkSubject.send(artData)
                await waitForReveal(presenter)

                // Both should have settled correctly
                let cachedImage = try #require(presenter.artworkImage)
                #expect(presenter.displayTitle == "New Song")
                #expect(presenter.displayArtist == "New Artist")

                // Now change artwork again
                let newArtData = try fixtureArtworkData(color: .blue)
                artworkSubject.send(newArtData)
                let newArtDeadline = ContinuousClock.now + .seconds(3)
                while presenter.artworkImage === cachedImage, ContinuousClock.now < newArtDeadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }

                #expect(presenter.artworkImage != nil)
                #expect(presenter.artworkImage !== cachedImage)
                // Title display still untouched
                #expect(presenter.displayTitle == "New Song")
            }
        }
    }
}
