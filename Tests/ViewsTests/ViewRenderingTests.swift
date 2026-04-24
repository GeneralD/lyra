import AppKit
import Combine
import Dependencies
import Domain
import Presenters
import SwiftUI
import Testing

@testable import Views

@MainActor
private func render<Content: View>(_ view: Content, size: CGSize) {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()
    _ = hostingView.fittingSize
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(3),
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - Stubs

private struct IdleTrackInteractor: TrackInteractor, @unchecked Sendable {
    let trackChange: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher()
    let artwork: AnyPublisher<Data?, Never> = Empty().eraseToAnyPublisher()
    let playbackPosition: AnyPublisher<PlaybackPosition, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect { .init(duration: 0) }
    var textLayout: TextLayout { .init(decodeEffect: .init(duration: 0)) }
    var artworkStyle: ArtworkStyle { .init() }
}

private struct DisabledRippleInteractor: WallpaperInteractor {
    var playbackMode: WallpaperPlaybackMode { .cycle }
    var rippleConfig: RippleStyle { .init(enabled: false) }
    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> { AsyncStream { $0.finish() } }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { Empty().eraseToAnyPublisher() }
}

private struct EnabledRippleInteractor: WallpaperInteractor {
    var playbackMode: WallpaperPlaybackMode { .cycle }
    var rippleConfig: RippleStyle { .init(enabled: true) }
    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> { AsyncStream { $0.finish() } }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { Empty().eraseToAnyPublisher() }
}

private struct FixtureTrackInteractor: TrackInteractor, @unchecked Sendable {
    let title: String
    let artist: String
    let lyrics: [String]
    var artworkData: Data? = nil
    var opacity: Double = 1.0

    var trackChange: AnyPublisher<TrackUpdate, Never> {
        Just(
            TrackUpdate(
                title: title,
                artist: artist,
                lyrics: .plain(lyrics),
                lyricsState: .resolved
            )
        ).eraseToAnyPublisher()
    }
    var artwork: AnyPublisher<Data?, Never> { Just(artworkData).eraseToAnyPublisher() }
    let playbackPosition: AnyPublisher<PlaybackPosition, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect { .init(duration: 0) }
    var textLayout: TextLayout { .init(decodeEffect: .init(duration: 0)) }
    var artworkStyle: ArtworkStyle { .init(opacity: opacity) }
}

// MARK: - HeaderView

@MainActor
@Suite("HeaderView rendering")
struct HeaderViewRenderingTests {
    @Test("idle state renders empty body")
    func idleState() {
        let presenter = withDependencies {
            $0.trackInteractor = IdleTrackInteractor()
        } operation: {
            HeaderPresenter()
        }
        // Don't call start() — titleState stays .idle
        render(HeaderView(presenter: presenter), size: CGSize(width: 600, height: 120))
        #expect(presenter.titleState == .idle)
    }

    @Test("artwork hidden when opacity is 0")
    func artworkHidden() async {
        let presenter = withDependencies {
            $0.trackInteractor = FixtureTrackInteractor(title: "Song", artist: "Artist", lyrics: [], opacity: 0)
        } operation: {
            HeaderPresenter()
        }
        presenter.start()
        defer { presenter.stop() }
        await waitUntil { presenter.displayTitle == "Song" }

        #expect(presenter.artworkOpacity == 0)
        render(HeaderView(presenter: presenter), size: CGSize(width: 600, height: 120))
    }

    @Test("artwork placeholder when no image data")
    func artworkPlaceholder() async {
        let presenter = withDependencies {
            $0.trackInteractor = FixtureTrackInteractor(title: "Song", artist: "Artist", lyrics: [])
        } operation: {
            HeaderPresenter()
        }
        presenter.start()
        defer { presenter.stop() }
        await waitUntil { presenter.displayTitle == "Song" }

        #expect(presenter.artworkOpacity > 0)
        #expect(presenter.artworkData == nil)
        render(HeaderView(presenter: presenter), size: CGSize(width: 600, height: 120))
    }

    @Test("artwork image rendered with valid data")
    func artworkWithImage() async {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        image.unlockFocus()
        let pngData = image.tiffRepresentation!

        let presenter = withDependencies {
            $0.trackInteractor = FixtureTrackInteractor(
                title: "Song", artist: "Artist", lyrics: [], artworkData: pngData
            )
        } operation: {
            HeaderPresenter()
        }
        presenter.start()
        defer { presenter.stop() }
        await waitUntil { presenter.artworkData != nil && presenter.displayTitle == "Song" }

        #expect(presenter.artworkData != nil)
        render(HeaderView(presenter: presenter), size: CGSize(width: 600, height: 120))
    }
}

// MARK: - RippleView

@MainActor
@Suite("RippleView rendering")
struct RippleViewRenderingTests {
    @Test("disabled ripple renders empty body")
    func disabledRipple() {
        let presenter = withDependencies {
            $0.wallpaperInteractor = DisabledRippleInteractor()
            $0.date = .init { Date(timeIntervalSinceReferenceDate: 0) }
        } operation: {
            RipplePresenter()
        }
        presenter.start()
        defer { presenter.stop() }

        #expect(!presenter.isEnabled)
        render(RippleView(presenter: presenter), size: CGSize(width: 400, height: 300))
    }

    @Test("enabled ripple renders canvas")
    func enabledRipple() {
        let presenter = withDependencies {
            $0.wallpaperInteractor = EnabledRippleInteractor()
            $0.date = .init { Date(timeIntervalSinceReferenceDate: 0) }
        } operation: {
            RipplePresenter()
        }
        presenter.start()
        defer { presenter.stop() }

        #expect(presenter.isEnabled)
        #expect(presenter.rippleState != nil)
        render(RippleView(presenter: presenter), size: CGSize(width: 400, height: 300))
    }
}

// MARK: - LyricsColumnView

@MainActor
@Suite("LyricsColumnView rendering")
struct LyricsColumnViewRenderingTests {
    @Test("empty lyrics renders without crash")
    func emptyLyrics() {
        let presenter = withDependencies {
            $0.trackInteractor = IdleTrackInteractor()
        } operation: {
            LyricsPresenter()
        }
        render(LyricsColumnView(presenter: presenter), size: CGSize(width: 600, height: 300))
    }

    @Test("populated lyrics renders lines")
    func populatedLyrics() async {
        let presenter = withDependencies {
            $0.trackInteractor = FixtureTrackInteractor(title: "Song", artist: "Artist", lyrics: ["Line 1", "Line 2", "Line 3"])
        } operation: {
            LyricsPresenter()
        }
        presenter.start()
        defer { presenter.stop() }
        await waitUntil { presenter.displayLyricLines == ["Line 1", "Line 2", "Line 3"] }

        render(LyricsColumnView(presenter: presenter), size: CGSize(width: 600, height: 300))
        #expect(presenter.displayLyricLines == ["Line 1", "Line 2", "Line 3"])
    }
}
