import Dependencies
import Domain
import Foundation

@MainActor
public final class LyricsPresenter: ObservableObject {
    @Published public private(set) var lyricsState: FetchState<LyricsContent> = .idle
    @Published public private(set) var displayLyricLines: [String] = []
    @Published public private(set) var activeLineIndex: Int?

    private var lyricEffects: [DecodeEffectState] = []
    private var decodeConfig: DecodeEffect?
    private var latestElapsed: TimeInterval?
    private var latestPlaybackRate: Double = 1.0

    @Dependency(\.trackInteractor) private var interactor

    public init() {}

    public func start() {
        decodeConfig = interactor.decodeEffectConfig
    }

    public func stop() {
        stopEffects()
    }

    public func receive(_ update: TrackUpdate) {
        latestElapsed = update.elapsed
        latestPlaybackRate = update.playbackRate

        switch update.lyricsState {
        case .idle:
            reset()
        case .loading:
            lyricsState = .loading
        case .resolved:
            guard let content = update.lyrics else { return }
            revealLyrics(content)
        case .notFound:
            lyricsState = .failure
            stopEffects()
            displayLyricLines = []
        }
        activeLineIndex = nil
    }

    /// Called from DisplayLink to keep activeLineIndex in sync at frame rate.
    public func updateActiveLineTick() {
        guard case .success(.timed(let lines)) = lyricsState else { return }
        guard latestPlaybackRate != 0 else { return }
        let index = latestElapsed.flatMap { elapsed in lines.lastIndex { $0.time <= elapsed } }
        guard index != activeLineIndex else { return }
        activeLineIndex = index
    }
}

extension LyricsPresenter {
    private func reset() {
        lyricsState = .idle
        activeLineIndex = nil
        stopEffects()
        displayLyricLines = []
    }

    private func stopEffects() {
        for effect in lyricEffects { effect.stop() }
        lyricEffects = []
    }

    private func revealLyrics(_ content: LyricsContent) {
        guard let decodeConfig else { return }
        lyricsState = .revealing(content)
        let texts: [String] =
            switch content {
            case .timed(let lines): lines.map(\.text)
            case .plain(let lines): lines
            }

        stopEffects()
        lyricEffects = texts.enumerated().map { index, _ in
            let effect = DecodeEffectState(config: decodeConfig)
            effect.onUpdate = { [weak self] displayText in
                guard let self, index < displayLyricLines.count else { return }
                displayLyricLines[index] = displayText
            }
            return effect
        }

        displayLyricLines = texts.map { _ in " " }

        for (index, text) in texts.enumerated() {
            lyricEffects[index].decode(to: text) { [weak self] in
                guard let self else { return }
                guard lyricEffects.allSatisfy({ !$0.isAnimating }) else { return }
                lyricsState = .success(content)
            }
        }
    }
}
