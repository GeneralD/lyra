import Domain
import Dependencies
import Foundation

@MainActor
public final class OverlayController {
    public let state = OverlayState()
    private var lastTrackKey: (String?, String?) = (nil, nil)
    private var fetchGeneration: Int = 0
    private var nowPlayingTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var latestNowPlaying: NowPlaying?

    private let titleEffect: DecodeEffectState
    private let artistEffect: DecodeEffectState
    private var lyricEffects: [DecodeEffectState] = []

    @Dependency(\.appStyle) private var config
    @Dependency(\.playbackUseCase) private var playbackService
    @Dependency(\.lyricsUseCase) private var lyricsService
    @Dependency(\.metadataUseCase) private var metadataService

    public init() {
        @Dependency(\.appStyle) var cfg
        titleEffect = DecodeEffectState(config: cfg.text.decodeEffect)
        artistEffect = DecodeEffectState(config: cfg.text.decodeEffect)
    }
}

public extension OverlayController {
    func start() {
        nowPlayingTask = Task { [weak self] in
            guard let self else { return }
            for await info in self.playbackService.observeNowPlaying() {
                guard !Task.isCancelled else { break }
                guard let info else { clearIfNeeded(); continue }
                latestNowPlaying = info
                updateArtwork(from: info)
                updateTrack(from: info)
                updateActiveLineIndex(from: info)
            }
        }
    }

    func stop() {
        nowPlayingTask?.cancel()
        fetchGeneration += 1
        titleEffect.stop()
        artistEffect.stop()
        lyricEffects.forEach { $0.stop() }
    }

    /// Called from DisplayLink to keep activeLineIndex in sync at frame rate
    func updateActiveLineTick() {
        guard let info = latestNowPlaying else { return }
        updateActiveLineIndex(from: info)
    }
}

private extension OverlayController {
    func clearIfNeeded() {
        guard lastTrackKey != (nil, nil) else { return }
        lastTrackKey = (nil, nil)
        latestNowPlaying = nil
        fetchGeneration += 1
        titleEffect.stop()
        artistEffect.stop()
        lyricEffects.forEach { $0.stop() }
        lyricEffects = []
        state.reset()
    }

    func updateArtwork(from info: NowPlaying) {
        guard info.artworkData != state.artworkData else { return }
        state.artworkData = info.artworkData
    }

    func updateTrack(from info: NowPlaying) {
        let trackKey = (info.title, info.artist)
        guard trackKey != lastTrackKey else { return }

        lastTrackKey = trackKey
        state.activeLineIndex = nil
        state.lyrics = .loading

        revealTitle(info.title)
        revealArtist(info.artist)

        fetchGeneration += 1
        let generation = fetchGeneration
        let service = lyricsService

        fetchTask = Task { [weak self] in
            // Debounce: wait for title/artist to stabilize
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, generation == self.fetchGeneration else { return }
            guard let title = info.title, let artist = info.artist else { return }

            // Step 1: Resolve metadata (fast)
            let rawTrack = Track(title: title, artist: artist, duration: info.duration)
            let candidates = await self.metadataService.resolveCandidates(track: rawTrack)
            guard generation == self.fetchGeneration else { return }
            if let resolved = candidates.first {
                self.revealTitle(resolved.title)
                if !resolved.artist.isEmpty { self.revealArtist(resolved.artist) }
            }

            // Step 2: Fetch lyrics (slow)
            let result = candidates.isEmpty
                ? await service.fetchLyrics(track: rawTrack)
                : await service.fetchLyrics(candidates: candidates)
            guard generation == self.fetchGeneration else { return }

            if let trackName = result.trackName { self.revealTitle(trackName) }
            if let artistName = result.artistName { self.revealArtist(artistName) }

            if let content = LyricsContent(from: result) {
                self.revealLyrics(content)
            } else {
                self.state.lyrics = .failure
                self.lyricEffects.forEach { $0.stop() }
                self.lyricEffects = []
                self.state.displayLyricLines = []
            }
            self.state.activeLineIndex = nil
        }
    }

    func updateActiveLineIndex(from info: NowPlaying) {
        guard case .success(let .timed(lines)) = state.lyrics else { return }
        guard info.playbackRate != 0 else { return }
        let index = info.elapsed.flatMap { elapsed in lines.lastIndex { $0.time <= elapsed } }
        guard index != state.activeLineIndex else { return }
        state.activeLineIndex = index
    }
}

// MARK: - Reveal animations

private extension OverlayController {
    func revealTitle(_ text: String?) {
        guard let text else {
            state.title = .idle
            state.displayTitle = " "
            return
        }
        state.title = .revealing(text)
        titleEffect.onUpdate = { [weak self] displayText in
            self?.state.displayTitle = displayText
        }
        titleEffect.decode(to: text) { [weak self] in
            self?.state.title = .success(text)
        }
    }

    func revealArtist(_ text: String?) {
        guard let text else {
            state.artist = .idle
            state.displayArtist = " "
            return
        }
        state.artist = .revealing(text)
        artistEffect.onUpdate = { [weak self] displayText in
            self?.state.displayArtist = displayText
        }
        artistEffect.decode(to: text) { [weak self] in
            self?.state.artist = .success(text)
        }
    }

    func revealLyrics(_ content: LyricsContent) {
        state.lyrics = .revealing(content)
        let texts: [String] = switch content {
        case .timed(let lines): lines.map(\.text)
        case .plain(let lines): lines
        }

        lyricEffects.forEach { $0.stop() }
        lyricEffects = texts.enumerated().map { index, text in
            let effect = DecodeEffectState(config: config.text.decodeEffect)
            effect.onUpdate = { [weak self] displayText in
                guard let self, index < state.displayLyricLines.count else { return }
                state.displayLyricLines[index] = displayText
            }
            return effect
        }

        state.displayLyricLines = texts.map { _ in " " }

        for (index, text) in texts.enumerated() {
            lyricEffects[index].decode(to: text) { [weak self] in
                guard let self else { return }
                guard lyricEffects.allSatisfy({ !$0.isAnimating }) else { return }
                state.lyrics = .success(content)
            }
        }
    }
}
