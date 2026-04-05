import Combine
import Dependencies
import Domain
import Foundation

public final class TrackInteractorImpl: @unchecked Sendable {
    @Dependency(\.playbackUseCase) private var playbackService
    @Dependency(\.lyricsUseCase) private var lyricsService
    @Dependency(\.metadataUseCase) private var metadataService
    @Dependency(\.configUseCase) private var configService

    private lazy var shared = nowPlayingPublisher.share()

    /// NowPlaying events with actual track info.
    /// Drops "degraded" updates where artist becomes empty for the same title —
    /// macOS MediaRemote clears artist on volume mute while keeping the title.
    private lazy var activeNowPlaying =
        shared
        .compactMap { $0 }
        .scan((previous: nil as NowPlaying?, current: nil as NowPlaying?)) { state, incoming in
            (previous: state.current, current: incoming)
        }
        .compactMap { state -> NowPlaying? in
            guard let current = state.current else { return nil }
            guard let previous = state.previous else { return current }
            // Same title but artist degraded from non-empty to empty → skip
            let prevArtist = previous.artist ?? ""
            let curArtist = current.artist ?? ""
            guard current.title == previous.title, !prevArtist.isEmpty, curArtist.isEmpty else {
                return current
            }
            return nil
        }
        .share()

    /// Emits on track change (title+artist) with metadata + lyrics resolution.
    ///
    /// Deduplication: macOS MediaRemote temporarily clears the artist field (to "")
    /// when system volume is set to 0, while keeping the title intact. On volume restore,
    /// the artist reappears. To avoid triggering DecodeEffect on these transient changes,
    /// compare by title only when either side has an empty/nil artist. When both have
    /// a non-empty artist, compare title + artist (to detect genuinely different tracks).
    public lazy var trackChange: AnyPublisher<TrackUpdate, Never> =
        activeNowPlaying
        .removeDuplicates {
            let prevArtist = ($0.artist ?? "")
            let curArtist = ($1.artist ?? "")
            guard !prevArtist.isEmpty, !curArtist.isEmpty else {
                return $0.title == $1.title
            }
            return $0.title == $1.title && prevArtist == curArtist
        }
        .map { [weak self] info -> AnyPublisher<TrackUpdate, Never> in
            guard let self else { return Empty().eraseToAnyPublisher() }
            return resolveTrack(from: info)
        }
        .switchToLatest()
        .share()
        .eraseToAnyPublisher()

    /// Emits when artwork data changes. Only emits when NowPlaying has track info.
    public lazy var artwork: AnyPublisher<Data?, Never> =
        activeNowPlaying
        .map(\.artworkData)
        .removeDuplicates()
        .eraseToAnyPublisher()

    /// Playback position: every NowPlaying update with track info.
    public lazy var playbackPosition: AnyPublisher<PlaybackPosition, Never> =
        activeNowPlaying
        .map { PlaybackPosition(elapsed: $0.elapsed, playbackRate: $0.playbackRate) }
        .eraseToAnyPublisher()

    public init() {}
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
            let capturedPlayback = playback
            let task = Task { @Sendable in
                for await info in capturedPlayback.observeNowPlaying() {
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
            artworkData: info.artworkData,
            duration: info.duration,
            lyricsState: .loading
        )

        guard let title = info.title, let artist = info.artist else {
            return Just(loading).eraseToAnyPublisher()
        }

        let rawTrack = Track(title: title, artist: artist, duration: info.duration)
        let metadata = metadataService
        let lyrics = lyricsService

        let artworkData = info.artworkData
        let duration = info.duration

        return Just(loading)
            .append(
                Deferred {
                    let subject = PassthroughSubject<TrackUpdate, Never>()
                    nonisolated(unsafe) let unsafeSubject = subject
                    return subject.handleEvents(receiveSubscription: { _ in
                        Task { @Sendable in
                            let candidates = await metadata.resolveCandidates(track: rawTrack)
                            let resolvedTitle = candidates.first?.title ?? title
                            let resolvedArtist =
                                candidates.first.map(\.artist).flatMap { $0.isEmpty ? nil : $0 }
                                ?? artist

                            // Emit metadata-resolved update immediately (lyrics still loading)
                            unsafeSubject.send(
                                TrackUpdate(
                                    title: resolvedTitle,
                                    artist: resolvedArtist,
                                    artworkData: artworkData,
                                    duration: duration,
                                    lyricsState: .loading
                                ))

                            let result =
                                candidates.isEmpty
                                ? await lyrics.fetchLyrics(track: rawTrack)
                                : await lyrics.fetchLyrics(candidates: candidates)

                            let finalTitle = result.trackName ?? resolvedTitle
                            let finalArtist = result.artistName ?? resolvedArtist
                            let content = lyrics.parseLyricsContent(from: result)

                            // Emit final update with lyrics
                            unsafeSubject.send(
                                TrackUpdate(
                                    title: finalTitle,
                                    artist: finalArtist,
                                    artworkData: artworkData,
                                    duration: duration,
                                    lyrics: content,
                                    lyricsState: content != nil ? .resolved : .notFound
                                ))
                            unsafeSubject.send(completion: .finished)
                        }
                    })
                }
                .delay(for: .milliseconds(300), scheduler: DispatchQueue.main)
            )
            .eraseToAnyPublisher()
    }
}
