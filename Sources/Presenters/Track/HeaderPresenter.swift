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

    public private(set) var titleStyle: TextAppearance = .init()
    public private(set) var artistStyle: TextAppearance = .init()
    public private(set) var artworkSize: Double = 96
    public private(set) var artworkOpacity: Double = 1.0

    private var titleEffect: DecodeEffectState?
    private var artistEffect: DecodeEffectState?
    private var titleTarget: String?
    private var artistTarget: String?
    private var artworkData: Data?
    private var processingColor: ColorStyle = .solid("#4ADE80FF")
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.trackInteractor) private var interactor

    public init() {}

    public func start() {
        let config = interactor.decodeEffectConfig
        let style = interactor.textLayout
        titleStyle = style.title
        artistStyle = style.artist
        titleColor = style.title.color
        artistColor = style.artist.color
        processingColor = config.processingColor
        artworkSize = interactor.artworkStyle.size
        artworkOpacity = interactor.artworkStyle.opacity
        titleEffect = DecodeEffectState(config: config)
        artistEffect = DecodeEffectState(config: config)

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
    }

    public func stop() {
        cancellables.removeAll()
        titleEffect?.stop()
        artistEffect?.stop()
    }
}

extension HeaderPresenter {
    private func receive(_ update: TrackUpdate) {
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
        guard let effect = titleEffect else { return }
        guard titleTarget != text else { return }
        titleTarget = text
        titlePhase = .revealing
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
        guard let effect = artistEffect else { return }
        guard artistTarget != text else { return }
        artistTarget = text
        artistPhase = .revealing
        effect.onUpdate = { [weak self] displayText in
            self?.displayArtist = displayText
        }
        effect.decode(to: text) { [weak self] in
            self?.artistPhase = .revealed
        }
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
        guard let effect = titleEffect, let text, !text.isEmpty else { return }
        titleTarget = nil
        titleColor = processingColor
        titlePhase = .revealing
        effect.onUpdate = { [weak self] displayText in
            self?.displayTitle = displayText
        }
        effect.startLoading(placeholderLength: text.count)
    }

    private func startProcessingArtist(_ text: String?) {
        guard let effect = artistEffect, let text, !text.isEmpty else { return }
        artistTarget = nil
        artistColor = processingColor
        artistPhase = .revealing
        effect.onUpdate = { [weak self] displayText in
            self?.displayArtist = displayText
        }
        effect.startLoading(placeholderLength: text.count)
    }
}
