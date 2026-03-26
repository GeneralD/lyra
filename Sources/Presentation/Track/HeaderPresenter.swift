import Dependencies
import Domain
import Foundation

@MainActor
public final class HeaderPresenter: ObservableObject {
    @Published public private(set) var displayTitle: String = " "
    @Published public private(set) var displayArtist: String = " "
    @Published public private(set) var artworkData: Data?
    @Published public private(set) var titleState: FetchState<String> = .idle
    @Published public private(set) var artistState: FetchState<String> = .idle

    private var titleEffect: DecodeEffectState?
    private var artistEffect: DecodeEffectState?

    @Dependency(\.trackInteractor) private var interactor

    public init() {}

    public func start() {
        let config = interactor.decodeEffectConfig
        titleEffect = DecodeEffectState(config: config)
        artistEffect = DecodeEffectState(config: config)
    }

    public func stop() {
        titleEffect?.stop()
        artistEffect?.stop()
    }

    public func receive(_ update: TrackUpdate) {
        updateArtwork(update.artworkData)
        revealTitle(update.title)
        revealArtist(update.artist)
    }
}

extension HeaderPresenter {
    private func updateArtwork(_ data: Data?) {
        guard data != artworkData else { return }
        artworkData = data
    }

    private func revealTitle(_ text: String?) {
        guard let text else {
            titleState = .idle
            displayTitle = " "
            return
        }
        guard let effect = titleEffect else { return }
        titleState = .revealing(text)
        effect.onUpdate = { [weak self] displayText in
            self?.displayTitle = displayText
        }
        effect.decode(to: text) { [weak self] in
            self?.titleState = .success(text)
        }
    }

    private func revealArtist(_ text: String?) {
        guard let text else {
            artistState = .idle
            displayArtist = " "
            return
        }
        guard let effect = artistEffect else { return }
        artistState = .revealing(text)
        effect.onUpdate = { [weak self] displayText in
            self?.displayArtist = displayText
        }
        effect.decode(to: text) { [weak self] in
            self?.artistState = .success(text)
        }
    }
}
