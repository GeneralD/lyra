import Combine
import Dependencies
import Domain
import Foundation
import os

/// Implementation of the `TrackInteractor` that manages the reactive track and artwork pipeline.
///
/// It observes now-playing information, resolves metadata and lyrics, and handles
/// artwork state preservation across track updates.
public final class TrackInteractorImpl: @unchecked Sendable {
    private let playbackService: any PlaybackUseCase
    private let lyricsService: any LyricsUseCase
    private let metadataService: any MetadataUseCase
    private let configService: any ConfigUseCase
    @Dependency(\.continuousClock) private var clock

    private lazy var shared = nowPlayingPublisher.share()

    /// How long a run of `nil` now-playing events must persist before the
    /// overlay clears. A `nil` means no client reported a title — the source
    /// app quit — while a paused client keeps reporting `rate = 0` info and a
    /// muted one still arrives with its title (#132), so neither pause nor
    /// mute ever produces it. The grace absorbs transient gaps (track-switch
    /// flashes, a MediaRemote hiccup) that would otherwise flicker the
    /// display (#360).
    private static let clearGrace: Duration = .seconds(5)

    /// The active now-playing element, or `nil` once no titled client has
    /// been seen for `clearGrace`. A `nil` is the display's clear boundary:
    /// it must not be emitted for a *suppressed* event — an event that arrives
    /// but is filtered out, like the artist-dropped report below — because a
    /// suppressed stream would eventually park on `nil` and clear a display
    /// that is still live. The scan therefore yields `NowPlaying??`: `nil`
    /// outer = swallowed event, `.some(nil)` = source gone, `.some(np)` =
    /// track element. Only the first `nil` of a run is emitted — a `nil`
    /// emitted downstream is the grace timer's arm, and re-arming it on every
    /// polling tick would never let it fire. Nothing else dedups here: pause
    /// (rate → 0) must still reach `playbackPosition`.
    private lazy var activeNowPlaying: AnyPublisher<NowPlaying?, Never> =
        shared
        .scan(
            (lastTrack: NowPlaying?.none, inNilRun: false, emit: NowPlaying??.none)
        ) { state, incoming in
            guard let incoming else {
                return (
                    lastTrack: state.lastTrack,
                    inNilRun: true,
                    emit: state.inNilRun ? nil : .some(nil)
                )
            }
            // Same title with the artist newly empty (e.g. system volume
            // mute): swallow the event, keeping the previous full report.
            let suppressed =
                state.lastTrack.map { last in
                    incoming.title == last.title
                        && !(last.artist ?? "").isEmpty
                        && (incoming.artist ?? "").isEmpty
                } ?? false
            return (
                lastTrack: incoming,
                inNilRun: false,
                emit: suppressed ? nil : .some(incoming)
            )
        }
        .compactMap { $0.emit }
        .map { [weak self] info -> AnyPublisher<NowPlaying?, Never> in
            guard let self else { return Empty().eraseToAnyPublisher() }
            guard info == nil else { return Just(info).eraseToAnyPublisher() }
            return clearedAfterGrace()
        }
        .switchToLatest()
        .share()
        .eraseToAnyPublisher()

    /// A publisher that emits `TrackUpdate` events whenever the active track
    /// changes, and one `.idle` update when the source has gone away for
    /// `clearGrace` — presenters treat it as "clear title, artist and
    /// lyrics" (#360).
    public lazy var trackChange: AnyPublisher<TrackUpdate, Never> =
        activeNowPlaying
        .removeDuplicates(by: Self.sameOptionalTrack)
        .map { [weak self] info -> AnyPublisher<TrackUpdate, Never> in
            guard let self else { return Empty().eraseToAnyPublisher() }
            guard let info else {
                return Just(TrackUpdate(lyricsState: .idle)).eraseToAnyPublisher()
            }
            return resolveTrack(from: info)
        }
        .switchToLatest()
        .share()
        .eraseToAnyPublisher()

    /// Keeps the last known artwork while the track is unchanged: system
    /// re-broadcasts (e.g. during display reconfiguration) often omit the
    /// artwork bytes, and a raw `map(\.artworkData)` would blank the artwork
    /// until the next event that happens to carry them (#265). A track change
    /// without artwork still clears it — as does the `nil` clear boundary,
    /// which emits `nil` data (#360).
    public lazy var artwork: AnyPublisher<Data?, Never> =
        activeNowPlaying
        .scan((track: NowPlaying?.none, data: Data?.none)) { state, incoming in
            guard let incoming else { return (track: nil, data: nil) }
            let isSameTrack = state.track.map { $0.title != nil && Self.sameTrack($0, incoming) } ?? false
            return (track: incoming, data: incoming.artworkData ?? (isSameTrack ? state.data : nil))
        }
        .map(\.data)
        .removeDuplicates()
        .eraseToAnyPublisher()

    /// Returns `true` when two `NowPlaying` values represent the same track.
    /// Treats `nil` and empty-string artist as the same value, so transitions
    /// between them (e.g. system volume mute) are not seen as track changes.
    static func sameTrack(_ lhs: NowPlaying, _ rhs: NowPlaying) -> Bool {
        let lhsArtist = lhs.artist ?? ""
        let rhsArtist = rhs.artist ?? ""
        guard !lhsArtist.isEmpty, !rhsArtist.isEmpty else {
            return lhs.title == rhs.title
        }
        return lhs.title == rhs.title && lhsArtist == rhsArtist
    }

    /// Returns `true` when two optional `NowPlaying` values carry the same
    /// track — `nil == nil`, so a source-gone run dedups to one boundary,
    /// while `nil` vs a track is distinct so a resumed track re-resolves.
    static func sameOptionalTrack(_ lhs: NowPlaying?, _ rhs: NowPlaying?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.some(let l), .some(let r)): return sameTrack(l, r)
        default: return false
        }
    }

    /// Emits a single `nil` after `clearGrace`, unless a new element supersedes
    /// it first (the enclosing `switchToLatest` cancels this task). Runs on the
    /// injected clock so tests advance it deterministically.
    private func clearedAfterGrace() -> AnyPublisher<NowPlaying?, Never> {
        let subject = PassthroughSubject<NowPlaying?, Never>()
        nonisolated(unsafe) let unsafeSubject = subject
        let clock = self.clock
        let taskLock = OSAllocatedUnfairLock(initialState: Task<Void, Never>?.none)
        return subject.handleEvents(
            receiveSubscription: { _ in
                taskLock.withLock { task in
                    task = Task { @Sendable in
                        try? await clock.sleep(for: Self.clearGrace)
                        guard !Task.isCancelled else { return }
                        unsafeSubject.send(nil)
                        unsafeSubject.send(completion: .finished)
                    }
                }
            },
            receiveCancel: {
                taskLock.withLock { task in
                    task?.cancel()
                    task = nil
                }
            }
        )
        .eraseToAnyPublisher()
    }

    /// A publisher that emits the current playback position.
    public lazy var playbackPosition: AnyPublisher<PlaybackPosition, Never> =
        activeNowPlaying
        .compactMap { $0 }
        .map { np in
            PlaybackPosition(
                rawElapsed: np.rawElapsed, timestamp: np.timestamp, playbackRate: np.playbackRate)
        }
        .eraseToAnyPublisher()

    public init() {
        @Dependency(\.playbackUseCase) var playback
        @Dependency(\.lyricsUseCase) var lyrics
        @Dependency(\.metadataUseCase) var metadata
        @Dependency(\.configUseCase) var config
        self.playbackService = playback
        self.lyricsService = lyrics
        self.metadataService = metadata
        self.configService = config
    }
}

extension TrackInteractorImpl: TrackInteractor {
    public var decodeEffectConfig: DecodeEffect {
        configService.appStyle.text.decodeEffect
    }

    public var textLayout: TextLayout {
        configService.appStyle.text
    }

    public var artworkStyle: ArtworkStyle {
        configService.appStyle.artwork
    }
}

extension TrackInteractorImpl {
    private var nowPlayingPublisher: AnyPublisher<NowPlaying?, Never> {
        let playback = playbackService
        return Deferred {
            let pub = PassthroughSubject<NowPlaying?, Never>()
            nonisolated(unsafe) let unsafePub = pub
            let task = Task { @Sendable in
                for await info in playback.observeNowPlaying() {
                    guard !Task.isCancelled else { break }
                    unsafePub.send(info)
                }
                unsafePub.send(completion: .finished)
            }
            return pub.handleEvents(receiveCancel: { task.cancel() })
        }
        .eraseToAnyPublisher()
    }

    private func resolveTrack(from info: NowPlaying) -> AnyPublisher<TrackUpdate, Never> {
        let loading = TrackUpdate(
            title: info.title,
            artist: info.artist,
            lyricsState: .loading
        )

        guard let title = info.title, let artist = info.artist else {
            return Just(loading).eraseToAnyPublisher()
        }

        let rawTrack = Track(title: title, artist: artist, duration: info.duration)
        let metadata = metadataService
        let lyrics = lyricsService
        let clock = self.clock
        let aiConfigured = configService.appStyle.ai != nil

        return Just(loading)
            .append(
                Deferred {
                    let subject = PassthroughSubject<TrackUpdate, Never>()
                    nonisolated(unsafe) let unsafeSubject = subject
                    let taskLock = OSAllocatedUnfairLock(initialState: Task<Void, Never>?.none)
                    return subject.handleEvents(
                        receiveSubscription: { _ in
                            taskLock.withLock { task in
                                task = Task { @Sendable in
                                    try? await clock.sleep(for: .milliseconds(300))
                                    guard !Task.isCancelled else {
                                        unsafeSubject.send(completion: .finished)
                                        return
                                    }

                                    // AI cache miss with an endpoint configured means
                                    // `resolveCandidates` will make a live API call — signal the
                                    // header to show its processing indicator for the round-trip (#57).
                                    if aiConfigured,
                                        await metadata.isAIMetadataCached(track: rawTrack) == false
                                    {
                                        guard !Task.isCancelled else {
                                            unsafeSubject.send(completion: .finished)
                                            return
                                        }
                                        unsafeSubject.send(
                                            TrackUpdate(
                                                title: title,
                                                artist: artist,
                                                lyricsState: .loading,
                                                aiResolving: true
                                            ))
                                    }

                                    let candidates = await metadata.resolveCandidates(track: rawTrack)
                                    guard !Task.isCancelled else {
                                        unsafeSubject.send(completion: .finished)
                                        return
                                    }

                                    let resolvedTitle = candidates.first?.title ?? title
                                    let resolvedArtist =
                                        candidates.first.map(\.artist).flatMap { $0.isEmpty ? nil : $0 }
                                        ?? artist

                                    unsafeSubject.send(
                                        TrackUpdate(
                                            title: resolvedTitle,
                                            artist: resolvedArtist,
                                            lyricsState: .loading
                                        ))

                                    // Always go through the candidates path, matching
                                    // `TrackHandlerImpl.infoWithLyrics`. Only that path
                                    // validates before caching and re-validates on read;
                                    // the single-track entry point does neither, so an
                                    // empty-candidates fallback into it could store a
                                    // loosely-matched LRCLIB row that then poisons every
                                    // later play (#326).
                                    let result = await lyrics.fetchLyrics(
                                        candidates: candidates.isEmpty ? [rawTrack] : candidates)
                                    guard !Task.isCancelled else {
                                        unsafeSubject.send(completion: .finished)
                                        return
                                    }

                                    let finalTitle = result.trackName.flatMap { $0.isEmpty ? nil : $0 } ?? title
                                    let finalArtist = result.artistName.flatMap { $0.isEmpty ? nil : $0 } ?? artist
                                    let content = lyrics.parseLyricsContent(from: result)

                                    unsafeSubject.send(
                                        TrackUpdate(
                                            title: finalTitle,
                                            artist: finalArtist,
                                            lyrics: content,
                                            lyricsState: content != nil ? .resolved : .notFound
                                        ))
                                    unsafeSubject.send(completion: .finished)
                                }
                            }
                        },
                        receiveCancel: {
                            taskLock.withLock { task in
                                task?.cancel()
                                task = nil
                            }
                        }
                    )
                }
            )
            .eraseToAnyPublisher()
    }
}
