import Dependencies
import Domain
import Foundation

public struct TrackInteractorImpl {
    @Dependency(\.playbackUseCase) private var playbackService
    @Dependency(\.lyricsUseCase) private var lyricsService
    @Dependency(\.metadataUseCase) private var metadataService
    @Dependency(\.configUseCase) private var configService

    public init() {}
}

extension TrackInteractorImpl: TrackInteractor {
    public func observeTrack() -> AsyncStream<TrackUpdate> {
        AsyncStream { continuation in
            let task = Task { @Sendable in
                var lastTrackKey: (String?, String?) = (nil, nil)

                for await info in playbackService.observeNowPlaying() {
                    guard !Task.isCancelled else { break }

                    guard let info else {
                        guard lastTrackKey != (nil, nil) else { continue }
                        lastTrackKey = (nil, nil)
                        continuation.yield(TrackUpdate())
                        continue
                    }

                    let trackKey = (info.title, info.artist)
                    let trackChanged = trackKey != lastTrackKey

                    guard trackChanged else {
                        // Same track — just update playback position
                        continuation.yield(
                            TrackUpdate(
                                title: info.title,
                                artist: info.artist,
                                artworkData: info.artworkData,
                                duration: info.duration,
                                elapsed: info.elapsed,
                                playbackRate: info.playbackRate,
                                lyricsState: .loading
                            ))
                        continue
                    }

                    lastTrackKey = trackKey

                    // Emit initial state with loading lyrics
                    continuation.yield(
                        TrackUpdate(
                            title: info.title,
                            artist: info.artist,
                            artworkData: info.artworkData,
                            duration: info.duration,
                            elapsed: info.elapsed,
                            playbackRate: info.playbackRate,
                            lyricsState: .loading
                        ))

                    // Debounce
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { break }

                    guard let title = info.title, let artist = info.artist else { continue }

                    // Resolve metadata
                    let rawTrack = Track(title: title, artist: artist, duration: info.duration)
                    let candidates = await metadataService.resolveCandidates(track: rawTrack)
                    guard !Task.isCancelled else { break }

                    let resolvedTitle = candidates.first?.title ?? title
                    let resolvedArtist = candidates.first.map(\.artist).flatMap { $0.isEmpty ? nil : $0 } ?? artist

                    // Emit metadata-resolved update
                    continuation.yield(
                        TrackUpdate(
                            title: resolvedTitle,
                            artist: resolvedArtist,
                            artworkData: info.artworkData,
                            duration: info.duration,
                            elapsed: info.elapsed,
                            playbackRate: info.playbackRate,
                            lyricsState: .loading
                        ))

                    // Fetch lyrics
                    let result =
                        candidates.isEmpty
                        ? await lyricsService.fetchLyrics(track: rawTrack)
                        : await lyricsService.fetchLyrics(candidates: candidates)
                    guard !Task.isCancelled else { break }

                    let finalTitle = result.trackName ?? resolvedTitle
                    let finalArtist = result.artistName ?? resolvedArtist
                    let content = LyricsContent(from: result)

                    continuation.yield(
                        TrackUpdate(
                            title: finalTitle,
                            artist: finalArtist,
                            artworkData: info.artworkData,
                            duration: info.duration,
                            elapsed: info.elapsed,
                            playbackRate: info.playbackRate,
                            lyrics: content,
                            lyricsState: content != nil ? .resolved : .notFound
                        ))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
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
