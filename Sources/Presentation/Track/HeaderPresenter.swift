import Combine
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

    public private(set) var titleStyle: TextAppearance = .init()
    public private(set) var artistStyle: TextAppearance = .init()
    public private(set) var artworkSize: Double = 96
    public private(set) var artworkOpacity: Double = 1.0

    private var titleEffect: DecodeEffectState?
    private var artistEffect: DecodeEffectState?
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.trackInteractor) private var interactor

    public init() {}

    public func start() {
        let config = interactor.decodeEffectConfig
        let style = interactor.textLayout
        titleStyle = style.title
        artistStyle = style.artist
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
                guard data != self?.artworkData else { return }
                self?.artworkData = data
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
        if update.lyricsState == .loading {
            artworkData = nil
        }
        revealTitle(update.title)
        revealArtist(update.artist)
    }

    private func revealTitle(_ text: String?) {
        guard let text else {
            titleState = .idle
            displayTitle = " "
            return
        }
        guard let effect = titleEffect else { return }
        guard titleState.value != text else { return }
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
        guard artistState.value != text else { return }
        artistState = .revealing(text)
        effect.onUpdate = { [weak self] displayText in
            self?.displayArtist = displayText
        }
        effect.decode(to: text) { [weak self] in
            self?.artistState = .success(text)
        }
    }
}
