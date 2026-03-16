import Domain
import Lyrics
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

    private var titleEffect: DecodeEffectState
    private var artistEffect: DecodeEffectState
    private var lyricEffects: [DecodeEffectState] = []

    @Dependency(\.config) private var config
    private let lyricsService = LyricsService()

    public init() {
        @Dependency(\.config) var cfg
        titleEffect = DecodeEffectState(config: cfg.text.decodeEffect)
        artistEffect = DecodeEffectState(config: cfg.text.decodeEffect)
    }
}

public extension OverlayController {
    func start() {
        nowPlayingTask = Task { [weak self] in
            guard let self else { return }
            @Dependency(\.nowPlayingProvider) var provider
            for await info in provider.stream() {
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
        fetchTask?.cancel()
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
        fetchTask?.cancel()
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
        fetchTask?.cancel()
        state.activeLineIndex = nil
        state.lyrics = .loading

        revealTitle(info.title)
        revealArtist(info.artist)

        fetchGeneration += 1
        let generation = fetchGeneration
        let service = lyricsService

        fetchTask = Task { [weak self] in
            let result: LyricsResult? = await {
                guard let title = info.title, let artist = info.artist else { return nil }
                return await service.fetch(title: title, artist: artist, duration: info.duration)
            }()
            guard !Task.isCancelled, let self, generation == fetchGeneration else { return }

            if let trackName = result?.trackName { revealTitle(trackName) }
            if let artistName = result?.artistName { revealArtist(artistName) }

            if let content = LyricsContent(from: result) {
                revealLyrics(content)
            } else {
                state.lyrics = .failure
                lyricEffects.forEach { $0.stop() }
                lyricEffects = []
                state.displayLyricLines = []
            }
            state.activeLineIndex = nil
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
