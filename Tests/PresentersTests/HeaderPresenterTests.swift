@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Stub

/// Reference-type backing for the style fields so a single `StubTrackInteractor`
/// value (copied on every `@Dependency` access, per swift-dependencies) can still
/// report updated config after `presenter.start()` — mutating the box is visible
/// through every copy that shares it.
private final class StubTrackInteractorStyleBox: @unchecked Sendable {
    var decodeEffectConfig: DecodeEffect
    var textLayout: TextLayout
    var artworkStyle: ArtworkStyle

    init(decodeEffectConfig: DecodeEffect, textLayout: TextLayout, artworkStyle: ArtworkStyle) {
        self.decodeEffectConfig = decodeEffectConfig
        self.textLayout = textLayout
        self.artworkStyle = artworkStyle
    }
}

private struct StubTrackInteractor: TrackInteractor, @unchecked Sendable {
    var trackChangePublisher: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher()
    private let styleBox: StubTrackInteractorStyleBox

    init(
        trackChangePublisher: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher(),
        decodeEffectConfig: DecodeEffect = .init(duration: 0),
        textLayout: TextLayout = .init(),
        artworkStyle: ArtworkStyle = .init()
    ) {
        self.trackChangePublisher = trackChangePublisher
        self.styleBox = StubTrackInteractorStyleBox(
            decodeEffectConfig: decodeEffectConfig, textLayout: textLayout, artworkStyle: artworkStyle)
    }

    var decodeEffectConfig: DecodeEffect { styleBox.decodeEffectConfig }
    var textLayout: TextLayout { styleBox.textLayout }
    var artworkStyle: ArtworkStyle { styleBox.artworkStyle }

    /// Replaces one or more style fields on the shared box, simulating a config
    /// reload landing after `start()` already ran.
    func updateStyle(
        textLayout: TextLayout? = nil, artworkStyle: ArtworkStyle? = nil,
        decodeEffectConfig: DecodeEffect? = nil
    ) {
        if let textLayout { styleBox.textLayout = textLayout }
        if let artworkStyle { styleBox.artworkStyle = artworkStyle }
        if let decodeEffectConfig { styleBox.decodeEffectConfig = decodeEffectConfig }
    }

    var trackChange: AnyPublisher<TrackUpdate, Never> { trackChangePublisher }
    var artwork: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { Empty().eraseToAnyPublisher() }
}

/// Stub `ConfigInteractor` whose `appStyleChanges` ping is externally controlled
/// via the injected subject, so tests can fire it after mutating the track stub.
private final class StubConfigInteractor: ConfigInteractor, @unchecked Sendable {
    private let appStyleChangesPublisher: AnyPublisher<Void, Never>

    init(appStyleChanges: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()) {
        self.appStyleChangesPublisher = appStyleChanges
    }

    var appStyleChanges: AnyPublisher<Void, Never> { appStyleChangesPublisher }
    var invalidConfig: AnyPublisher<ConfigReloadFailure?, Never> { Just(nil).eraseToAnyPublisher() }
    func start() {}
    func stop() {}
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

    @Suite("config hot reload")
    struct HotReload {
        @MainActor
        @Test("appStyleChanges 発火で titleStyle/artworkSize/titleColor が新値に更新される")
        func appliesUpdatedStyleOnPing() async {
            let initialLayout = TextLayout(
                title: TextAppearance(fontSize: 18, fontWeight: "bold", color: .solid("#111111FF")),
                artist: TextAppearance(fontWeight: "medium")
            )
            let updatedLayout = TextLayout(
                title: TextAppearance(fontSize: 32, fontWeight: "black", color: .solid("#222222FF")),
                artist: TextAppearance(fontWeight: "medium")
            )
            let trackStub = StubTrackInteractor(
                decodeEffectConfig: .init(duration: 0),
                textLayout: initialLayout,
                artworkStyle: ArtworkStyle(size: 96, opacity: 1.0)
            )
            let appStyleChanges = PassthroughSubject<Void, Never>()

            await withDependencies {
                $0.trackInteractor = trackStub
                $0.configInteractor = StubConfigInteractor(
                    appStyleChanges: appStyleChanges.eraseToAnyPublisher())
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                #expect(presenter.titleStyle.fontSize == 18)
                #expect(presenter.artworkSize == 96)

                // Subscription must not be re-wired — only the shared style stub
                // mutates, then the ping alone drives the refresh.
                trackStub.updateStyle(
                    textLayout: updatedLayout, artworkStyle: ArtworkStyle(size: 200, opacity: 0.4))
                appStyleChanges.send(())

                await waitUntil { presenter.titleStyle.fontSize == 32 }

                #expect(presenter.titleStyle.fontSize == 32)
                #expect(presenter.titleStyle.fontWeight == "black")
                #expect(presenter.titleColor == .solid("#222222FF"))
                #expect(presenter.artworkSize == 200)
                #expect(presenter.artworkOpacity == 0.4)
            }
        }

        @MainActor
        @Test("AI 処理中の appStyleChanges は titleColor/artistColor に processingColor を維持する")
        func keepsProcessingColorDuringAIResolving() async {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let appStyleChanges = PassthroughSubject<Void, Never>()
            let initialProcessing: ColorStyle = .solid("#FF00FFFF")
            let updatedProcessing: ColorStyle = .solid("#00FFFFFF")

            let trackStub = StubTrackInteractor(
                trackChangePublisher: subject.eraseToAnyPublisher(),
                decodeEffectConfig: .init(duration: 0, processingColor: initialProcessing)
            )

            await withDependencies {
                $0.trackInteractor = trackStub
                $0.configInteractor = StubConfigInteractor(
                    appStyleChanges: appStyleChanges.eraseToAnyPublisher())
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                subject.send(
                    TrackUpdate(title: "Song", artist: "Artist", lyricsState: .loading, aiResolving: true))
                await waitUntil { presenter.titleColor == initialProcessing }

                // Config reloads while AI resolution is in flight; processingColor
                // itself may also change (e.g. edited config), but the effective
                // titleColor/artistColor must stay pinned to processingColor,
                // never fall back to the normal configured color mid-scramble.
                trackStub.updateStyle(
                    decodeEffectConfig: .init(duration: 0, processingColor: updatedProcessing))
                appStyleChanges.send(())

                await waitUntil { presenter.titleColor == updatedProcessing }

                #expect(presenter.titleColor == updatedProcessing)
                #expect(presenter.artistColor == updatedProcessing)
                #expect(presenter.titlePhase == .revealing)
            }
        }
    }

    @Suite("decode effect rebuild at reveal boundary (Codex review)")
    struct DecodeEffectRebuildAtRevealBoundary {
        /// Deterministic stand-in for the default `ZeroRandomSource` test value —
        /// spelled out explicitly here because this test's whole assertion rests
        /// on index 0 of the pool always being picked.
        private struct AlwaysZeroRandomSource: RandomSource {
            func next(below count: Int) -> Int { 0 }
        }

        @MainActor
        @Test("processing 開始のたびに live config の charset で effect を作り直す")
        func rebuildsEffectOnEachProcessingStart() async {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let appStyleChanges = PassthroughSubject<Void, Never>()

            let trackStub = StubTrackInteractor(
                trackChangePublisher: subject.eraseToAnyPublisher(),
                decodeEffectConfig: .init(duration: 0.8, charsets: [.symbols])
            )

            await withDependencies {
                $0.trackInteractor = trackStub
                $0.configInteractor = StubConfigInteractor(
                    appStyleChanges: appStyleChanges.eraseToAnyPublisher())
                $0.continuousClock = ImmediateClock()
                $0.randomSource = AlwaysZeroRandomSource()
            } operation: {
                let presenter = HeaderPresenter()
                presenter.start()

                // charsets = [.symbols] → pool[0] == "†" → placeholderLength 2 → "††".
                subject.send(
                    TrackUpdate(title: "XY", artist: nil, lyricsState: .loading, aiResolving: true))
                await waitUntil { presenter.displayTitle == "††" }
                #expect(presenter.displayTitle == "††")

                // config.toml edit: charset switches to greek. applyStyle() must NOT
                // touch the in-flight effect (no interruption of the scramble).
                trackStub.updateStyle(decodeEffectConfig: .init(duration: 0.8, charsets: [.greek]))
                appStyleChanges.send(())

                // A fresh aiResolving update re-enters startProcessingTitle (it always
                // clears titleTarget), which is a reveal/processing boundary — the
                // effect must be rebuilt from the now-updated live config.
                subject.send(
                    TrackUpdate(title: "XY", artist: nil, lyricsState: .loading, aiResolving: true))
                // charsets = [.greek] → pool[0] == "Α" → "ΑΑ".
                await waitUntil { presenter.displayTitle == "ΑΑ" }

                #expect(presenter.displayTitle == "ΑΑ")

                presenter.stop()
            }
        }
    }
}
