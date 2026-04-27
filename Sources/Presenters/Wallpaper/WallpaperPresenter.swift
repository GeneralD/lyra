@preconcurrency import AVFoundation
import Combine
import Dependencies
import Domain
import Foundation

@MainActor
public final class WallpaperPresenter: ObservableObject {
    @Published public private(set) var wallpaperURL: URL?
    @Published public private(set) var startTime: TimeInterval?
    @Published public private(set) var endTime: TimeInterval?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var player: AVPlayer?

    private(set) var items: [ResolvedWallpaperItem] = []
    private var mode: WallpaperPlaybackMode = .cycle
    private var currentIndex: Int = 0

    let controller = WallpaperPlaybackController()
    private var loadTask: Task<Void, Never>?
    private var sleepWakeCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.wallpaperInteractor) private var interactor
    @Dependency(\.randomSource) private var randomSource

    public init() {
        controller.$player.assign(to: &$player)
        controller.onAdvanceRequested = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleAdvanceRequest()
            }
        }
    }

    public func start() {
        loadTask?.cancel()
        isLoading = true
        items = []
        currentIndex = 0
        mode = interactor.playbackMode
        observeSleepWake()
        let stream = interactor.resolvedWallpapers()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await resolved in stream {
                let wasEmpty = items.isEmpty
                items.append(resolved)
                if wasEmpty {
                    isLoading = false
                    currentIndex = 0
                    await activateCurrentItem()
                }
            }
            if items.isEmpty {
                isLoading = false
            }
        }
    }

    public func stop() {
        loadTask?.cancel()
        loadTask = nil
        controller.stop()
        sleepWakeCancellable?.cancel()
        sleepWakeCancellable = nil
        cancellables.removeAll()
        items = []
        currentIndex = 0
    }

    /// Register a side-effect to run once when the player becomes available.
    /// The wireframe uses this to drive `OverlayWindow.attachPlayerLayer`. Since
    /// the controller now keeps a stable AVPlayer instance across item swaps,
    /// the layer only needs to be attached once.
    public func onPlayerAvailable(_ handler: @escaping @MainActor (AVPlayer) -> Void) {
        $player
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { player in handler(player) }
            .store(in: &cancellables)
    }
}

extension WallpaperPresenter {
    private func activateCurrentItem() async {
        guard items.indices.contains(currentIndex) else {
            wallpaperURL = nil
            startTime = nil
            endTime = nil
            controller.stop()
            return
        }
        let item = items[currentIndex]
        wallpaperURL = item.url
        startTime = item.start
        endTime = item.end
        await controller.play(item: item)
    }

    private func handleAdvanceRequest() async {
        guard items.count > 1 else {
            controller.loopCurrent()
            return
        }
        await advanceToNextItem()
    }

    private func observeSleepWake() {
        guard sleepWakeCancellable == nil else { return }
        sleepWakeCancellable = interactor.systemSleepChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .willSleep: self?.player?.pause()
                case .didWake: self?.player?.play()
                }
            }
    }

    private func advanceToNextItem() async {
        guard items.count > 1 else { return }
        currentIndex = nextIndex(from: currentIndex)
        await activateCurrentItem()
    }

    private func nextIndex(from current: Int) -> Int {
        switch mode {
        case .cycle:
            return (current + 1) % items.count
        case .shuffle:
            let candidates = (0..<items.count).filter { $0 != current }
            guard !candidates.isEmpty else { return current }
            return candidates[randomSource.next(below: candidates.count)]
        }
    }
}
