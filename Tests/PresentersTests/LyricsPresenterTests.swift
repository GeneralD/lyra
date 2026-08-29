@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import TestSupport
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
    var trackChangePublisher: AnyPublisher<TrackUpdate, Never>
    var playbackPositionPublisher: AnyPublisher<PlaybackPosition, Never>
    private let styleBox: StubTrackInteractorStyleBox

    init(
        trackChangePublisher: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher(),
        playbackPositionPublisher: AnyPublisher<PlaybackPosition, Never> = Empty().eraseToAnyPublisher(),
        decodeEffectConfig: DecodeEffect = .init(duration: 0),
        textLayout: TextLayout = .init(),
        artworkStyle: ArtworkStyle = .init()
    ) {
        self.trackChangePublisher = trackChangePublisher
        self.playbackPositionPublisher = playbackPositionPublisher
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
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { playbackPositionPublisher }
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

    @Suite("config hot reload", .timeLimit(.minutes(1)))
    struct HotReload {
        @MainActor
        @Test("appStyleChanges 発火で lyricStyle/highlightStyle が新値に更新される")
        func appliesUpdatedStyleOnPing() async {
            let initialLayout = TextLayout(
                lyric: TextAppearance(fontSize: 16, fontWeight: "regular"),
                highlight: TextAppearance(fontSize: 16, color: .solid("#111111FF"))
            )
            let updatedLayout = TextLayout(
                lyric: TextAppearance(fontSize: 20, fontWeight: "bold"),
                highlight: TextAppearance(fontSize: 20, color: .solid("#FFD700FF"))
            )
            let trackStub = StubTrackInteractor(textLayout: initialLayout)
            let appStyleChanges = PassthroughSubject<Void, Never>()

            await withDependencies {
                $0.trackInteractor = trackStub
                $0.configInteractor = StubConfigInteractor(
                    appStyleChanges: appStyleChanges.eraseToAnyPublisher())
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                #expect(presenter.lyricStyle.fontSize == 16)
                #expect(presenter.highlightStyle.color == .solid("#111111FF"))

                // Subscription must not be re-wired — only the shared style stub
                // mutates, then the ping alone drives the refresh.
                trackStub.updateStyle(textLayout: updatedLayout)
                appStyleChanges.send(())

                await settle(presenter.$lyricStyle) { $0.fontSize == 20 }

                #expect(presenter.lyricStyle.fontSize == 20)
                #expect(presenter.lyricStyle.fontWeight == "bold")
                #expect(presenter.highlightStyle.color == .solid("#FFD700FF"))
            }
        }
    }

    @Suite("receive TrackUpdate", .timeLimit(.minutes(1)))
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
                await settle(presenter.$lyricsState) { $0.isLoading }

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
                await settle(presenter.$lyricsState) { $0 == .failure }

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
                await settle(presenter.$lyricsState) { $0.isLoading }

                // Then idle
                subject.send(TrackUpdate(lyricsState: .idle))
                await settle(presenter.$lyricsState) { $0.isIdle }

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
                await settle(presenter.$lyricsState) { $0.isSuccess }

                #expect(presenter.lyricsState == .success(content))
                #expect(presenter.displayLyricLines.count == 2)
            }
        }
    }

    @Suite("updateActiveLineTick", .timeLimit(.minutes(1)))
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
                await settle(presenter.$lyricsState) { $0.isSuccess }

                // Send a paused playback position (rate = 0).
                positionSubject.send(PlaybackPosition(rawElapsed: 6, playbackRate: 0))

                // activeLineIndex must remain nil — both before sink delivery
                // (latestRawElapsed still nil → interpolatedElapsed nil → no index
                // change) and after delivery (latestPlaybackRate == 0 → early
                // return). Tick a bounded number of times and assert the
                // condition never held — a negative tick window (#349).
                #expect(
                    await tickUntil(100, tick: presenter.updateActiveLineTick) {
                        presenter.activeLineIndex != nil
                    } == false)
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
                await settle(presenter.$lyricsState) { $0.isSuccess }

                // Send position at 6s — should highlight Line B (time=5)
                positionSubject.send(PlaybackPosition(rawElapsed: 6, playbackRate: 1.0))

                #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 1 })
                #expect(presenter.activeLineIndex == 1)
            }
        }

        @MainActor
        @Test("interpolates elapsed from snapshot (rawElapsed + timestamp + playbackRate)")
        func interpolatesFromSnapshot() async throws {
            let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
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
                $0.date = .constant(fixedNow)
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                trackSubject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
                await settle(presenter.$lyricsState) { $0.isSuccess }

                // Snapshot from 7s ago: rawElapsed=0, rate=1.0
                // Interpolated at fixedNow: 0 + 1.0 * 7.0 = 7.0 → Line B (time=5)
                positionSubject.send(
                    PlaybackPosition(
                        rawElapsed: 0,
                        timestamp: fixedNow.addingTimeInterval(-7),
                        playbackRate: 1.0))

                #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 1 })
                #expect(presenter.activeLineIndex == 1)
            }
        }

        @MainActor
        @Test("captures the injected date generator at init, not at start (#272)")
        func capturesDateGeneratorAtInit() async throws {
            let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let positionSubject = PassthroughSubject<PlaybackPosition, Never>()
            let lines: [LyricLine] = [
                .init(time: 0, text: "Line A"),
                .init(time: 5, text: "Line B"),
                .init(time: 10, text: "Line C"),
            ]
            let content = LyricsContent.timed(lines)

            // Construct the presenter inside the dependency scope so the date
            // generator is captured here. `start()` is deliberately called
            // OUTSIDE the scope below: if the generator were resolved in
            // `start()` it would fall back to the live clock and the
            // fixed-now interpolation would be wrong.
            let presenter = withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: trackSubject.eraseToAnyPublisher(),
                    playbackPositionPublisher: positionSubject.eraseToAnyPublisher(),
                    textLayout: TextLayout(decodeEffect: .init(duration: 0))
                )
                $0.date = .constant(fixedNow)
            } operation: {
                LyricsPresenter()
            }

            presenter.start()

            trackSubject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
            await settle(presenter.$lyricsState) { $0.isSuccess }

            // Snapshot from 7s ago at the captured fixedNow → 7.0 → Line B.
            positionSubject.send(
                PlaybackPosition(
                    rawElapsed: 0,
                    timestamp: fixedNow.addingTimeInterval(-7),
                    playbackRate: 1.0))

            #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 1 })
            #expect(presenter.activeLineIndex == 1)
        }

        @MainActor
        @Test("seek back updates active line to an earlier line (#272)")
        func seekBackUpdatesActiveLine() async throws {
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
                await settle(presenter.$lyricsState) { $0.isSuccess }

                // Advance to Line C (index 2)
                positionSubject.send(PlaybackPosition(rawElapsed: 12, timestamp: nil, playbackRate: 1.0))
                #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 2 })
                #expect(presenter.activeLineIndex == 2)

                // Seek back to Line A (index 0)
                positionSubject.send(PlaybackPosition(rawElapsed: 3, timestamp: nil, playbackRate: 1.0))
                #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 0 })
                #expect(presenter.activeLineIndex == 0)
            }
        }

        @MainActor
        @Test("advances multiple lines in a single tick (#272)")
        func advancesMultipleLinesInOneTick() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let positionSubject = PassthroughSubject<PlaybackPosition, Never>()
            let lines: [LyricLine] = [
                .init(time: 0, text: "A"),
                .init(time: 2, text: "B"),
                .init(time: 4, text: "C"),
                .init(time: 6, text: "D"),
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
                await settle(presenter.$lyricsState) { $0.isSuccess }

                // Jump directly to elapsed=7 — should land on Line D (index 3)
                positionSubject.send(PlaybackPosition(rawElapsed: 7, timestamp: nil, playbackRate: 1.0))
                #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 3 })
                #expect(presenter.activeLineIndex == 3)
            }
        }

        @MainActor
        @Test("falls back to rawElapsed when timestamp is nil")
        func fallsBackWhenTimestampMissing() async throws {
            let trackSubject = PassthroughSubject<TrackUpdate, Never>()
            let positionSubject = PassthroughSubject<PlaybackPosition, Never>()
            let lines: [LyricLine] = [
                .init(time: 0, text: "A"),
                .init(time: 5, text: "B"),
                .init(time: 10, text: "C"),
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
                await settle(presenter.$lyricsState) { $0.isSuccess }

                // timestamp nil → rawElapsed used verbatim (no interpolation)
                positionSubject.send(PlaybackPosition(rawElapsed: 7, timestamp: nil, playbackRate: 1.0))

                #expect(await tickUntil(tick: presenter.updateActiveLineTick) { presenter.activeLineIndex == 1 })
                #expect(presenter.activeLineIndex == 1)
            }
        }
    }

    @Suite("receive edge cases", .timeLimit(.minutes(1)))
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

                // Record every lyricsState transition from here on.
                let transitions = Collector<FetchState<LyricsContent>>()
                let cancellable = presenter.$lyricsState.dropFirst().sink { transitions.append($0) }

                // Send resolved with nil lyrics — guarded by `guard let content
                // = update.lyrics else { return }`, so it must produce no
                // transition at all.
                subject.send(TrackUpdate(lyrics: nil, lyricsState: .resolved))

                // Sentinel: a real resolved update through the same
                // trackChange pipeline. Both updates are delivered by the same
                // `.receive(on: .main)` sink in send order, so once the
                // sentinel's own `.success` lands, the nil-lyrics update above
                // has already been fully processed — anything it produced
                // would already be in `transitions`.
                let sentinelContent = LyricsContent.plain(["Sentinel"])
                subject.send(TrackUpdate(lyrics: sentinelContent, lyricsState: .resolved))
                await settle(presenter.$lyricsState) { $0 == .success(sentinelContent) }

                // Only the sentinel's own transitions were recorded — the
                // nil-lyrics guard produced none.
                #expect(transitions.values == [.revealing(sentinelContent), .success(sentinelContent)])
                _ = cancellable
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
                await settle(presenter.$lyricsState) { $0.isSuccess }
                #expect(presenter.lyricsState == .success(content))

                // Track state transitions after the duplicate send.
                let transitions = Collector<FetchState<LyricsContent>>()
                let cancellable = presenter.$lyricsState.dropFirst().sink { transitions.append($0) }

                // Send same lyrics again — guard prevents re-reveal
                subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))

                // Sentinel: a distinct lyrics update through the same
                // trackChange pipeline. Because both sends are delivered by
                // the same `.receive(on: .main)` sink in order, the duplicate
                // above has already been fully (non-)processed by the time
                // the sentinel's own `.success` lands.
                let sentinelContent = LyricsContent.plain(["Sentinel line"])
                subject.send(TrackUpdate(lyrics: sentinelContent, lyricsState: .resolved))
                await settle(presenter.$lyricsState) { $0 == .success(sentinelContent) }

                #expect(
                    transitions.values == [.revealing(sentinelContent), .success(sentinelContent)],
                    "should not re-enter .revealing for duplicate lyrics")
                _ = cancellable
            }
        }
    }

    @Suite("stop", .timeLimit(.minutes(1)))
    struct Stop {
        @MainActor
        @Test("stop cancels subscriptions and effects")
        func stopCancels() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let content = LyricsContent.plain(["Line 1"])

            // Cancellation spy: `receiveCancel` fires when `stop()`'s
            // `cancellables.removeAll()` tears down the sink built on top of
            // this publisher — Combine propagates `cancel()` synchronously up
            // the operator chain, through `.receive(on: .main)`, to here.
            let cancelled = Collector<Void>()
            let trackChangePublisher =
                subject
                .handleEvents(receiveCancel: { cancelled.append(()) })
                .eraseToAnyPublisher()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: trackChangePublisher,
                    textLayout: TextLayout(decodeEffect: .init(duration: 0))
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
                await settle(presenter.$lyricsState) { $0.isSuccess }
                #expect(presenter.lyricsState == .success(content))

                presenter.stop()
                await cancelled.waitForCount(1)

                // The subscription is gone, so this send reaches no
                // subscriber and runs synchronously to nothing — no wait
                // needed to observe that state did not change.
                let newContent = LyricsContent.plain(["New Line"])
                subject.send(TrackUpdate(lyrics: newContent, lyricsState: .resolved))
                #expect(
                    presenter.lyricsState == .success(content),
                    "State should not change after stop")
            }
        }
    }
}
