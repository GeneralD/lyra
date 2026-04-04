import ArgumentParser
import AsyncRunnableCommand
import Dependencies
import Domain
import Foundation

struct TrackCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "track",
        abstract: "Show currently playing track info as JSON"
    )

    @Flag(name: [.short, .long], help: "Resolve metadata via MusicBrainz/regex")
    var resolve = false

    @Flag(name: [.short, .long], help: "Include lyrics (fetches from LRCLIB)")
    var lyrics = false

    func run() async throws {
        print(encode(await info))
    }
}

extension TrackCommand {
    private var info: NowPlayingInfo {
        get async {
            @Dependency(\.playbackUseCase) var playbackUseCase

            guard let nowPlaying = await playbackUseCase.fetchNowPlaying(),
                let rawTitle = nowPlaying.title, let rawArtist = nowPlaying.artist
            else {
                return .init()
            }

            let track = Track(title: rawTitle, artist: rawArtist, duration: nowPlaying.duration)
            let (title, artist, candidates) = await resolvedMetadata(track: track)

            guard lyrics else {
                return .init(
                    title: title, artist: artist,
                    duration: nowPlaying.duration, elapsedTime: nowPlaying.elapsed
                )
            }

            return await infoWithLyrics(
                nowPlaying: nowPlaying, track: track,
                title: title, artist: artist, candidates: candidates
            )
        }
    }

    private func resolvedMetadata(track: Track) async -> (String, String, [Track]) {
        @Dependency(\.metadataUseCase) var metadataUseCase

        guard resolve || lyrics else { return (track.title, track.artist, []) }

        let candidates = await metadataUseCase.resolveCandidates(track: track)
        let title = candidates.first?.title ?? track.title
        let artist = candidates.first?.artist ?? track.artist
        return (title, artist, candidates)
    }

    private func infoWithLyrics(
        nowPlaying: NowPlaying, track: Track,
        title: String, artist: String, candidates: [Track]
    ) async -> NowPlayingInfo {
        @Dependency(\.lyricsUseCase) var lyricsUseCase

        let result = await lyricsUseCase.fetchLyrics(
            candidates: candidates.isEmpty ? [track] : candidates
        )
        let timedLines = LyricsContent(from: result).flatMap { c -> [LyricLine]? in
            guard case .timed(let lines) = c else { return nil }
            return lines
        }

        return .init(
            title: result.trackName ?? title,
            artist: result.artistName ?? artist,
            album: result.albumName,
            duration: nowPlaying.duration,
            elapsedTime: nowPlaying.elapsed,
            lyrics: result.plainLyrics,
            syncedLyrics: timedLines,
            currentLyric: timedLines.flatMap { lines in
                nowPlaying.elapsed.flatMap { t in lines.last { $0.time <= t }?.text }
            }
        )
    }
}

private func encode(_ info: NowPlayingInfo) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? encoder.encode(info)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}
