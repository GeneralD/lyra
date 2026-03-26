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

    /// Emits on track change (title+artist) with metadata + lyrics resolution.
    public lazy var trackChange: AnyPublisher<TrackUpdate, Never> =
        shared
        .compactMap { $0 }
        .removeDuplicates { $0.title == $1.title && $0.artist == $1.artist }
        .map { [weak self] info -> AnyPublisher<TrackUpdate, Never> in
            guard let self else { return Empty().eraseToAnyPublisher() }
            return resolveTrack(from: info)
        }
        .switchToLatest()
        .share()
        .eraseToAnyPublisher()

    /// Emits when artwork data changes.
    public lazy var artwork: AnyPublisher<Data?, Never> =
        shared
        .map { $0?.artworkData }
        .removeDuplicates()
        .eraseToAnyPublisher()

    /// Playback position: every NowPlaying update, just elapsed + rate.
    public lazy var playbackPosition: AnyPublisher<PlaybackPosition, Never> =
        shared
        .compactMap { $0 }
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
                    Future<TrackUpdate, Never> { promise in
                        nonisolated(unsafe) let unsafePromise = promise
                        Task { @Sendable in
                            let candidates = await metadata.resolveCandidates(track: rawTrack)
                            let resolvedTitle = candidates.first?.title ?? title
                            let resolvedArtist =
                                candidates.first.map(\.artist).flatMap { $0.isEmpty ? nil : $0 } ?? artist

                            let result =
                                candidates.isEmpty
                                ? await lyrics.fetchLyrics(track: rawTrack)
                                : await lyrics.fetchLyrics(candidates: candidates)

                            let finalTitle = result.trackName ?? resolvedTitle
                            let finalArtist = result.artistName ?? resolvedArtist
                            let content = LyricsContent(from: result)

                            unsafePromise(
                                .success(
                                    TrackUpdate(
                                        title: finalTitle,
                                        artist: finalArtist,
                                        artworkData: artworkData,
                                        duration: duration,
                                        lyrics: content,
                                        lyricsState: content != nil ? .resolved : .notFound
                                    )))
                        }
                    }
                }
                .delay(for: .milliseconds(300), scheduler: DispatchQueue.main)
            )
            .eraseToAnyPublisher()
    }
}
