import Combine
import Dependencies
import Domain
import Foundation

@MainActor
public final class LyricsPresenter: ObservableObject {
    @Published public private(set) var lyricsState: FetchState<LyricsContent> = .idle
    @Published public private(set) var displayLyricLines: [String] = []
    @Published public private(set) var activeLineIndex: Int?

    public private(set) var lyricStyle: TextAppearance = .init()
    public private(set) var highlightStyle: TextAppearance = .init()

    private var lyricEffects: [DecodeEffectState] = []
    private var decodeConfig: DecodeEffect?
    private var latestElapsed: TimeInterval?
    private var latestPlaybackRate: Double = 1.0
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.trackInteractor) private var interactor

    public init() {}

    public func start() {
        let layout = interactor.textLayout
        decodeConfig = layout.decodeEffect
        lyricStyle = layout.lyric
        highlightStyle = layout.highlight

        interactor.trackChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.receive(update)
            }
            .store(in: &cancellables)

        interactor.playbackPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] position in
                self?.latestElapsed = position.elapsed
                self?.latestPlaybackRate = position.playbackRate
            }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
        stopEffects()
    }

    // MARK: - Column layout

    public struct LyricColumn: Identifiable {
        public let id: Int
        public let entries: [Entry]
        public let highlightIndex: Int?

        public struct Entry: Identifiable {
            public let index: Int
            public let displayText: String
            public let sourceText: String
            public var id: Int { index }
        }
    }

    public struct ColumnsResult {
        public let columns: [LyricColumn]
        public let columnWidth: Double
        public let columnGap: Double
    }

    public func columns(in bounds: CGSize, lineHeight: Double) -> ColumnsResult {
        let layout = ColumnLayout(width: bounds.width, lyricsHeight: bounds.height, lineHeight: lineHeight)
        guard let content = lyricsState.value else {
            return ColumnsResult(columns: [], columnWidth: layout.columnWidth, columnGap: layout.columnGap)
        }
        let sourceTexts: [String] =
            switch content {
            case .timed(let lines): lines.map(\.text)
            case .plain(let lines): lines
            }
        let highlightIndex: Int? =
            switch content {
            case .timed: activeLineIndex
            case .plain: nil
            }
        let lpc = layout.linesPerColumn
        let count = layout.columnsNeeded(for: sourceTexts.count)
        let cols = (0..<count).map { col in
            let start = col * lpc
            let end = min(start + lpc, sourceTexts.count)
            let entries = (start..<end).map { i in
                LyricColumn.Entry(
                    index: i,
                    displayText: i < displayLyricLines.count ? displayLyricLines[i] : sourceTexts[i],
                    sourceText: sourceTexts[i]
                )
            }
            return LyricColumn(id: col, entries: entries, highlightIndex: highlightIndex)
        }
        return ColumnsResult(columns: cols, columnWidth: layout.columnWidth, columnGap: layout.columnGap)
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
    private func receive(_ update: TrackUpdate) {
        switch update.lyricsState {
        case .idle:
            reset()
        case .loading:
            lyricsState = .loading
        case .resolved:
            guard let content = update.lyrics else { return }
            guard lyricsState.value != content else { return }
            revealLyrics(content)
        case .notFound:
            lyricsState = .failure
            stopEffects()
            displayLyricLines = []
        }
        activeLineIndex = nil
    }

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

        let effects = lyricEffects
        for (index, text) in texts.enumerated() {
            effects[index].decode(to: text) { [weak self] in
                guard let self else { return }
                guard effects.allSatisfy({ !$0.isAnimating }) else { return }
                lyricsState = .success(content)
            }
        }
    }
}
