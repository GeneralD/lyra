import AppKit
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

    @Suite("duplicate track suppression", .timeLimit(.minutes(1)))
    struct DuplicateTrack {
        @MainActor
        @Test("sending same title twice does not re-trigger decode effect")
        func sameTitleTwiceStaysSuccess() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let update = TrackUpdate(title: "Same", artist: "Artist")
            // A different update through the same trackChange → receive(_:) →
            // revealTitle/revealArtist pipeline, sent right after the duplicate.
            let sentinelUpdate = TrackUpdate(title: "Sentinel", artist: "SentinelArtist")

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
                await settle(presenter.$titlePhase) { $0 == .revealed }
                await settle(presenter.$artistPhase) { $0 == .revealed }
                #expect(presenter.displayTitle == "Same")
                #expect(presenter.displayArtist == "Artist")

                // Record every phase transition from here on, so a duplicate-send
                // re-trigger (a spurious `.revealing`) is caught even though it
                // would self-heal back to `.revealed` before any assertion runs.
                let titlePhases = Collector<RevealPhase>()
                let artistPhases = Collector<RevealPhase>()
                let titleCancellable = presenter.$titlePhase.dropFirst().sink { titlePhases.append($0) }
                let artistCancellable = presenter.$artistPhase.dropFirst().sink { artistPhases.append($0) }

                // Second send with identical title/artist — must be deduped (no-op).
                subject.send(update)

                // Sentinel: Combine delivers on one queue in send order, so its
                // `.revealed` arriving proves the duplicate send above already
                // finished being processed (a no-op, per the guard in revealTitle/
                // revealArtist).
                subject.send(sentinelUpdate)
                await settle(presenter.$titlePhase) { $0 == .revealed }
                await settle(presenter.$artistPhase) { $0 == .revealed }
                #expect(presenter.displayTitle == "Sentinel")
                #expect(presenter.displayArtist == "SentinelArtist")

                // The only recorded transitions are the sentinel's own
                // `.revealing` → `.revealed` — the duplicate produced none.
                #expect(titlePhases.values == [.revealing, .revealed])
                #expect(artistPhases.values == [.revealing, .revealed])

                titleCancellable.cancel()
                artistCancellable.cancel()
            }
        }
    }

    @Suite("artwork stream", .timeLimit(.minutes(1)))
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
                await settle(presenter.$titlePhase) { $0 == .revealed }
                await settle(presenter.$artistPhase) { $0 == .revealed }
                #expect(presenter.displayTitle == "Song")
                #expect(presenter.artworkImage == nil)

                // Send artwork
                let imageData = try fixtureArtworkData()
                artworkSubject.send(imageData)
                await settle(presenter.$artworkImage) { $0 != nil }

                let cachedImage = try #require(presenter.artworkImage)
                // Title display must remain unchanged
                #expect(presenter.displayTitle == "Song")
                #expect(presenter.displayArtist == "Band")

                // Record every artworkImage publish from here, so a duplicate-send
                // re-decode (a fresh `NSImage` built from identical bytes) is
                // caught even though its identity alone can't distinguish "no
                // publish happened" from "republished the same-looking image".
                let artworkPublishes = Collector<Void>()
                let cancellable = presenter.$artworkImage.dropFirst().sink { _ in artworkPublishes.append(()) }

                // Duplicate send with identical bytes — must be deduped (no
                // re-decode), per the guard in receiveArtwork(_:).
                artworkSubject.send(imageData)

                // Sentinel: genuinely different artwork bytes, through the same
                // artwork → receiveArtwork(_:) pipeline. Combine delivers on one
                // queue in send order, so this publish proves the duplicate
                // above already finished being processed.
                let sentinelData = try fixtureArtworkData(color: .blue)
                artworkSubject.send(sentinelData)
                await settle(presenter.$artworkImage) { $0 !== cachedImage }

                // Exactly one publish recorded — the sentinel's. A duplicate
                // re-decode would have shown up as a second publish here.
                #expect(artworkPublishes.count == 1)
                #expect(presenter.displayTitle == "Song")

                cancellable.cancel()
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
                await settle(presenter.$titlePhase) { $0 == .revealed }
                await settle(presenter.$artistPhase) { $0 == .revealed }

                // Both should have settled correctly
                let cachedImage = try #require(presenter.artworkImage)
                #expect(presenter.displayTitle == "New Song")
                #expect(presenter.displayArtist == "New Artist")

                // Now change artwork again
                let newArtData = try fixtureArtworkData(color: .blue)
                artworkSubject.send(newArtData)
                await settle(presenter.$artworkImage) { $0 !== cachedImage }

                #expect(presenter.artworkImage != nil)
                #expect(presenter.artworkImage !== cachedImage)
                // Title display still untouched
                #expect(presenter.displayTitle == "New Song")
            }
        }
    }
}
