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

    public private(set) var titleStyle: TextAppearance = .init()
    public private(set) var artistStyle: TextAppearance = .init()
    public private(set) var artworkSize: Double = 96
    public private(set) var artworkOpacity: Double = 1.0

    private var titleEffect: DecodeEffectState?
    private var artistEffect: DecodeEffectState?
    private var titleTarget: String?
    private var artistTarget: String?
    private var artworkData: Data?
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
        revealTitle(update.title)
        revealArtist(update.artist)
    }

    private func receiveArtwork(_ data: Data?) {
        guard data != artworkData else { return }
        artworkData = data
        artworkImage = data.flatMap(NSImage.init(data:))
    }

    private func revealTitle(_ text: String?) {
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
