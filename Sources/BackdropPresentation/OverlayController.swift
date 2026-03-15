import BackdropDomain
import BackdropLyrics
import Dependencies
import Foundation

/// Manages NowPlaying observation, lyrics fetching, and state transitions.
/// Separated from window management to keep UI layer thin.
@MainActor
public final class OverlayController {
    public let state = OverlayState()
    private var lastTrackKey: (String?, String?) = (nil, nil)
    private var fetchGeneration: Int = 0
    private var revealTimers: [AnyHashable: Timer] = [:]
    private var nowPlayingTask: Task<Void, Never>?

    @Dependency(\.nowPlayingProvider) private var nowPlayingProvider
    @Dependency(\.config) private var config
    private let lyricsService = LyricsService()

    public init() {}
}

extension OverlayController {
    public func start() {
        nowPlayingTask = Task { [weak self] in
            guard let self else { return }
            @Dependency(\.nowPlayingProvider) var provider
            for await info in provider.stream() {
                guard !Task.isCancelled else { break }
                guard let info else { clearIfNeeded(); continue }
                updateArtwork(from: info)
                updateTrack(from: info)
                updateActiveLineIndex(from: info)
            }
        }
    }

    public func stop() {
        nowPlayingTask?.cancel()
        revealTimers.values.forEach { $0.invalidate() }
        revealTimers.removeAll()
    }
}

extension OverlayController {
    private func clearIfNeeded() {
        guard lastTrackKey != (nil, nil) else { return }
        lastTrackKey = (nil, nil)
        state.reset()
    }

    private func updateArtwork(from info: NowPlaying) {
        guard info.artworkData != state.artworkData else { return }
        state.artworkData = info.artworkData
    }

    private func updateTrack(from info: NowPlaying) {
        let trackKey = (info.title, info.artist)
        guard trackKey != lastTrackKey else { return }

        lastTrackKey = trackKey
        reveal(\.title, to: info.title)
        reveal(\.artist, to: info.artist)
        state.activeLineIndex = nil
        state.lyrics = .loading
        fetchGeneration += 1
        let generation = fetchGeneration

        let service = lyricsService
        Task {
            let result: LyricsResult? = await {
                guard let title = info.title, let artist = info.artist else { return nil }
                return await service.fetch(title: title, artist: artist, duration: info.duration)
            }()
            guard generation == self.fetchGeneration else { return }
            if let trackName = result?.trackName { reveal(\.title, to: trackName) }
            if let artistName = result?.artistName { reveal(\.artist, to: artistName) }
            if let content = LyricsContent(from: result) {
                revealLyrics(content)
            } else {
                state.lyrics = .failure
            }
            state.activeLineIndex = nil
        }
    }

    private func updateActiveLineIndex(from info: NowPlaying) {
        guard case .success(let .timed(lines)) = state.lyrics else { return }
        guard info.playbackRate != 0 else { return }
        let index = info.elapsed.flatMap { elapsed in lines.lastIndex { $0.time <= elapsed } }
        guard index != state.activeLineIndex else { return }
        state.activeLineIndex = index
    }
}

// MARK: - Reveal transition

extension OverlayController {
    private func reveal(_ keyPath: ReferenceWritableKeyPath<OverlayState, FetchState<String>>, to text: String?) {
        guard let text else { return }
        let key = keyPath.hashValue
        revealTimers[key]?.invalidate()
        state[keyPath: keyPath] = .revealing(text)
        revealTimers[key] = Timer.scheduledTimer(withTimeInterval: config.text.decodeEffect.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state[keyPath: keyPath] = .success(text)
                self?.revealTimers.removeValue(forKey: key)
            }
        }
    }

    private func revealLyrics(_ content: LyricsContent) {
        let key = "lyrics"
        revealTimers[key]?.invalidate()
        state.lyrics = .revealing(content)
        revealTimers[key] = Timer.scheduledTimer(withTimeInterval: config.text.decodeEffect.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state.lyrics = .success(content)
                self?.revealTimers.removeValue(forKey: key)
            }
        }
    }
}
