import Combine
import Dependencies
import Domain
import Foundation

public final class TrackInteractorImpl: @unchecked Sendable {
    @Dependency(\.playbackUseCase) private var playbackService
    @Dependency(\.lyricsUseCase) private var lyricsService
    @Dependency(\.metadataUseCase) private var metadataService
    @Dependency(\.configUseCase) private var configService

    public init() {}
}

extension TrackInteractorImpl: TrackInteractor {
    public var track: AnyPublisher<TrackUpdate, Never> {
        nowPlayingPublisher
            .removeDuplicates { $0?.title == $1?.title && $0?.artist == $1?.artist }
            .map { [weak self] info -> AnyPublisher<TrackUpdate, Never> in
                guard let self, let info else {
                    return Just(TrackUpdate()).eraseToAnyPublisher()
                }
                return resolveTrack(from: info)
            }
            .switchToLatest()
            .share()
            .eraseToAnyPublisher()
    }

    public var decodeEffectConfig: DecodeEffect {
        configService.loadAppStyle().text.decodeEffect
    }

    public var textLayout: TextLayout {
        configService.loadAppStyle().text
    }

    public var artworkStyle: ArtworkStyle {
        configService.loadAppStyle().artwork
    }
}

extension TrackInteractorImpl {
    /// Bridge AsyncStream to Combine publisher
    private var nowPlayingPublisher: AnyPublisher<NowPlaying?, Never> {
        let playback = playbackService
        return Deferred {
            let pub = PassthroughSubject<NowPlaying?, Never>()
            nonisolated(unsafe) let sendable = pub
            let task = Task {
                for await info in playback.observeNowPlaying() {
                    guard !Task.isCancelled else { break }
                    sendable.send(info)
                }
                sendable.send(completion: .finished)
            }
            return pub.handleEvents(receiveCancel: { task.cancel() })
        }
        .eraseToAnyPublisher()
    }

    /// For a given NowPlaying, emit loading → metadata-resolved → lyrics-resolved
    private func resolveTrack(from info: NowPlaying) -> AnyPublisher<TrackUpdate, Never> {
        let loading = TrackUpdate(
            title: info.title,
            artist: info.artist,
            artworkData: info.artworkData,
            duration: info.duration,
            elapsed: info.elapsed,
            playbackRate: info.playbackRate,
            lyricsState: .loading
        )

        guard let title = info.title, let artist = info.artist else {
            return Just(loading).eraseToAnyPublisher()
        }

        let rawTrack = Track(title: title, artist: artist, duration: info.duration)
        let metadata = metadataService
        let lyrics = lyricsService

        return Just(loading)
            .append(
                Deferred {
                    Future<TrackUpdate, Never> { promise in
                        nonisolated(unsafe) let promise = promise
                        Task {
                            let candidates = await metadata.resolveCandidates(track: rawTrack)
                            let resolvedTitle = candidates.first?.title ?? title
                            let resolvedArtist = candidates.first.map(\.artist).flatMap { $0.isEmpty ? nil : $0 } ?? artist

                            let result =
                                candidates.isEmpty
                                ? await lyrics.fetchLyrics(track: rawTrack)
                                : await lyrics.fetchLyrics(candidates: candidates)

                            let finalTitle = result.trackName ?? resolvedTitle
                            let finalArtist = result.artistName ?? resolvedArtist
                            let content = LyricsContent(from: result)

                            promise(
                                .success(
                                    TrackUpdate(
                                        title: finalTitle,
                                        artist: finalArtist,
                                        artworkData: info.artworkData,
                                        duration: info.duration,
                                        elapsed: info.elapsed,
                                        playbackRate: info.playbackRate,
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
