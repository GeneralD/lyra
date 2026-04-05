import Dependencies
import Domain
import Foundation

public struct TrackHandlerImpl {
    public init() {}
}

extension TrackHandlerImpl: TrackHandler {
    public func fetchInfo(query: TrackQuery) async -> NowPlayingInfo {
        @Dependency(\.playbackUseCase) var playbackUseCase

        guard let nowPlaying = await playbackUseCase.fetchNowPlaying(),
            let rawTitle = nowPlaying.title, let rawArtist = nowPlaying.artist
        else {
            return .init()
        }

        let track = Track(title: rawTitle, artist: rawArtist, duration: nowPlaying.duration)
        let (title, artist, candidates) = await resolvedMetadata(
            track: track, resolve: query.resolve || query.lyrics
        )

        guard query.lyrics else {
            return .init(
                title: title, artist: artist,
                duration: nowPlaying.duration, elapsedTime: playbackUseCase.elapsedTime(for: nowPlaying)
            )
        }

        return await infoWithLyrics(
            nowPlaying: nowPlaying, track: track,
            title: title, artist: artist, candidates: candidates
        )
    }
}

extension TrackHandlerImpl {
    private func resolvedMetadata(track: Track, resolve: Bool) async -> (String, String, [Track]) {
        guard resolve else { return (track.title, track.artist, []) }

        @Dependency(\.metadataUseCase) var metadataUseCase
        let candidates = await metadataUseCase.resolveCandidates(track: track)
        let title = candidates.first?.title ?? track.title
        let artist = candidates.first?.artist ?? track.artist
        return (title, artist, candidates)
    }

    private func infoWithLyrics(
        nowPlaying: NowPlaying, track: Track,
        title: String, artist: String, candidates: [Track]
    ) async -> NowPlayingInfo {
        @Dependency(\.playbackUseCase) var playbackUseCase
        @Dependency(\.lyricsUseCase) var lyricsUseCase

        let result = await lyricsUseCase.fetchLyrics(
            candidates: candidates.isEmpty ? [track] : candidates
        )
        let timedLines = lyricsUseCase.parseLyricsContent(from: result).flatMap { c -> [LyricLine]? in
            guard case .timed(let lines) = c else { return nil }
            return lines
        }

        let elapsed = playbackUseCase.elapsedTime(for: nowPlaying)
        return .init(
            title: result.trackName ?? title,
            artist: result.artistName ?? artist,
            album: result.albumName,
            duration: nowPlaying.duration,
            elapsedTime: elapsed,
            lyrics: result.plainLyrics,
            syncedLyrics: timedLines,
            currentLyric: timedLines.flatMap { lines in
                elapsed.flatMap { t in lines.last { $0.time <= t }?.text }
            }
        )
    }
}
