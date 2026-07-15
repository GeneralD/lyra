import AppKit
import Combine
import Dependencies
import Domain
import Foundation

@MainActor
public final class HeaderPresenter: ObservableObject {
    @Published public private(set) var displayTitle: String = " "
    @Published public private(set) var displayArtist: String = " "
    @Published public private(set) var artworkImage: NSImage?
    // Payload-less reveal lifecycle: the View gates header visibility on
    // `titlePhase != .idle`, and tests observe the settle to `.revealed`. The
    // target strings the decode aims at live in private `titleTarget` /
    // `artistTarget` below — they are an internal dedup concern, not public
    // state (#275).
    @Published public private(set) var titlePhase: RevealPhase = .idle
    @Published public private(set) var artistPhase: RevealPhase = .idle
    // Effective foreground colors. They equal the configured title/artist
    // colors except while the AI extractor is resolving (cache miss), when both
    // switch to `decodeEffect.processingColor` and the header scrambles in it,
    // then settle back to the normal color on the resolved text (#57).
    @Published public private(set) var titleColor: ColorStyle = .solid("#FFFFFFD9")
    @Published public private(set) var artistColor: ColorStyle = .solid("#FFFFFFD9")

    // font / size / color 系は config のホットリロードで再反映されるため
    // @Published (View の再描画を誘発する) にする (#41 PR2)。
    @Published public private(set) var titleStyle: TextAppearance = .init()
    @Published public private(set) var artistStyle: TextAppearance = .init()
    @Published public private(set) var artworkSize: Double = 96
    @Published public private(set) var artworkOpacity: Double = 1.0

    private var titleEffect: DecodeEffectState?
    private var artistEffect: DecodeEffectState?
    private var titleTarget: String?
    private var artistTarget: String?
    private var artworkData: Data?
    private var processingColor: ColorStyle = .solid("#4ADE80FF")
    // AI 処理中（scramble 中）かどうか。applyStyle() が titleColor/artistColor を
    // 再適用する際、処理中は processingColor を維持し、通常時は configured color に
    // 戻すために必要 (#57 の色を config ホットリロードで壊さないため)。
    private var isAIProcessing = false
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.trackInteractor) private var interactor
    @Dependency(\.configInteractor) private var configInteractor

    public init() {}

    public func start() {
        applyStyle()

        interactor.trackChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.receive(update)
            }
            .store(in: &cancellables)

        interactor.artwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.receiveArtwork(data)
            }
            .store(in: &cancellables)

        // 購読は起動時に一度だけ張る。config 変更のたびに appStyleChanges が
        // 発火し applyStyle() を呼ぶだけで、購読自体は張り替えない。
        configInteractor.appStyleChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.applyStyle()
            }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
        titleEffect?.stop()
        artistEffect?.stop()
    }

    /// 冪等に config 値を再反映する。起動時に一度、以降は `appStyleChanges`
    /// ping の都度呼ばれる。AI 処理中は processingColor を維持する。
    private func applyStyle() {
        let style = interactor.textLayout
        titleStyle = style.title
        artistStyle = style.artist
        artworkSize = interactor.artworkStyle.size
        artworkOpacity = interactor.artworkStyle.opacity
        processingColor = interactor.decodeEffectConfig.processingColor
        titleColor = isAIProcessing ? processingColor : style.title.color
        artistColor = isAIProcessing ? processingColor : style.artist.color
    }
}

extension HeaderPresenter {
    private func receive(_ update: TrackUpdate) {
        isAIProcessing = update.aiResolving
        guard update.aiResolving else {
            revealTitle(update.title)
            revealArtist(update.artist)
            return
        }
        startProcessing(title: update.title, artist: update.artist)
    }

    private func receiveArtwork(_ data: Data?) {
        guard data != artworkData else { return }
        artworkData = data
        artworkImage = data.flatMap(NSImage.init(data:))
    }

    private func revealTitle(_ text: String?) {
        titleColor = titleStyle.color
        guard let text else {
            titleTarget = nil
            titlePhase = .idle
            displayTitle = " "
            return
        }
        guard titleTarget != text else { return }
        titleTarget = text
        titlePhase = .revealing
        let effect = makeTitleEffect()
        effect.onUpdate = { [weak self] displayText in
            self?.displayTitle = displayText
        }
        effect.decode(to: text) { [weak self] in
            self?.titlePhase = .revealed
        }
    }

    private func revealArtist(_ text: String?) {
        artistColor = artistStyle.color
        guard let text else {
            artistTarget = nil
            artistPhase = .idle
            displayArtist = " "
            return
        }
        guard artistTarget != text else { return }
        artistTarget = text
        artistPhase = .revealing
        let effect = makeArtistEffect()
        effect.onUpdate = { [weak self] displayText in
            self?.displayArtist = displayText
        }
        effect.decode(to: text) { [weak self] in
            self?.artistPhase = .revealed
        }
    }

    /// `titleEffect`/`artistEffect` を reveal / processing 開始の都度、live config
    /// から作り直す。`DecodeEffectState` は `duration`/`charsets` を init で `let` と
    /// して焼き付けるため、`applyStyle()` からいじっても反映されない — reveal の
    /// dedup guard を通過し新しいアニメの開始が確定した後（進行中のアニメを壊さない
    /// 地点）で作り直すことで、config.toml の decode_effect 編集が次回の reveal /
    /// processing から反映されるようにする。`applyStyle()` はこの effect に一切触れ
    /// ないままなので、進行中のスクランブルは config ping で中断されない。
    private func makeTitleEffect() -> DecodeEffectState {
        titleEffect?.stop()
        let effect = DecodeEffectState(config: interactor.decodeEffectConfig)
        titleEffect = effect
        return effect
    }

    private func makeArtistEffect() -> DecodeEffectState {
        artistEffect?.stop()
        let effect = DecodeEffectState(config: interactor.decodeEffectConfig)
        artistEffect = effect
        return effect
    }
}

extension HeaderPresenter {
    /// Switches the header into the AI-processing state: both fields scramble
    /// indefinitely in `processingColor` until the resolved update arrives and
    /// `revealTitle` / `revealArtist` settle them. `*Target` is cleared so the
    /// settle is never deduped away even when the AI result equals the raw text.
    private func startProcessing(title: String?, artist: String?) {
        startProcessingTitle(title)
        startProcessingArtist(artist)
    }

    private func startProcessingTitle(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        titleTarget = nil
        titleColor = processingColor
        titlePhase = .revealing
        let effect = makeTitleEffect()
        effect.onUpdate = { [weak self] displayText in
            self?.displayTitle = displayText
        }
        effect.startLoading(placeholderLength: text.count)
    }

    private func startProcessingArtist(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        artistTarget = nil
        artistColor = processingColor
        artistPhase = .revealing
        let effect = makeArtistEffect()
        effect.onUpdate = { [weak self] displayText in
            self?.displayArtist = displayText
        }
        effect.startLoading(placeholderLength: text.count)
    }
}
