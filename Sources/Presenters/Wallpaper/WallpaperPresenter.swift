@preconcurrency import AVFoundation
import Combine
import Dependencies
import Domain
import Foundation

@MainActor
public final class WallpaperPresenter: ObservableObject {
    /// Delay before the loading indicator becomes visible. Fast loads finish
    /// before this and never show the spinner; slow loads (network downloads,
    /// yt-dlp) cross the threshold and reveal it.
    static let loadingIndicatorDelay: Duration = .milliseconds(300)

    @Published public private(set) var wallpaperURL: URL?
    @Published public private(set) var startTime: TimeInterval?
    @Published public private(set) var endTime: TimeInterval?
    @Published public private(set) var wallpaperScale: Double = 1.0
    @Published public private(set) var isLoading: Bool = false
    /// Debounced view of `isLoading`: stays `false` until the load has been in
    /// flight for `loadingIndicatorDelay`. Drives the spinner overlay.
    @Published public private(set) var showLoadingIndicator: Bool = false
    @Published public private(set) var player: AVPlayer?

    private(set) var items: [ResolvedWallpaperItem] = []
    private var mode: WallpaperPlaybackMode = .cycle
    private var currentIndex: Int = 0

    let controller = WallpaperPlaybackController()
    private var loadTask: Task<Void, Never>?
    private var indicatorTask: Task<Void, Never>?
    private var sleepWakeCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.wallpaperInteractor) private var interactor
    @Dependency(\.randomSource) private var randomSource
    @Dependency(\.continuousClock) private var clock

    public init() {
        controller.$player.assign(to: &$player)
        controller.onAdvanceRequested = { [weak self] in
            Task { @MainActor in
                await self?.handleAdvanceRequest()
            }
        }
    }

    /// Cancel outstanding tasks even if `stop()` was never called. Without this,
    /// an `indicatorTask` suspended on `clock.sleep(...)` would keep the clock
    /// (and itself) alive past the presenter's lifetime — under CI parallelism
    /// this leaks tasks across test suites and saturates the main actor.
    deinit {
        loadTask?.cancel()
        indicatorTask?.cancel()
    }

    public func start() {
        loadTask?.cancel()
        setLoading(true)
        items = []
        currentIndex = 0
        wallpaperScale = 1.0
        mode = interactor.playbackMode
        observeSleepWake()
        let stream = interactor.resolvedWallpapers()
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await resolved in stream {
                let wasEmpty = items.isEmpty
                items.append(resolved)
                if wasEmpty {
                    setLoading(false)
                    currentIndex = 0
                    await activateCurrentItem()
                }
            }
            if items.isEmpty {
                setLoading(false)
            }
        }
    }

    public func stop() {
        loadTask?.cancel()
        loadTask = nil
        indicatorTask?.cancel()
        indicatorTask = nil
        isLoading = false
        showLoadingIndicator = false
        controller.stop()
        sleepWakeCancellable?.cancel()
        sleepWakeCancellable = nil
        cancellables.removeAll()
        items = []
        currentIndex = 0
        wallpaperScale = 1.0
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

    public func onWallpaperScaleChange(_ handler: @escaping @MainActor (Double) -> Void) {
        $wallpaperScale
            .receive(on: DispatchQueue.main)
            .sink { scale in handler(scale) }
            .store(in: &cancellables)
    }
}

extension WallpaperPresenter {
    private func activateCurrentItem() async {
        guard items.indices.contains(currentIndex) else {
            wallpaperURL = nil
            startTime = nil
            endTime = nil
            wallpaperScale = 1.0
            controller.stop()
            return
        }
        let item = items[currentIndex]
        wallpaperURL = item.url
        startTime = item.start
        endTime = item.end
        wallpaperScale = item.scale
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

    /// Updates `isLoading` and debounces `showLoadingIndicator`. Loads that
    /// finish before `loadingIndicatorDelay` never reveal the spinner.
    private func setLoading(_ loading: Bool) {
        isLoading = loading
        indicatorTask?.cancel()
        indicatorTask = nil
        guard loading else {
            showLoadingIndicator = false
            return
        }
        let clock = clock
        indicatorTask = Task { @MainActor [weak self] in
            try? await clock.sleep(for: Self.loadingIndicatorDelay)
            guard !Task.isCancelled else { return }
            self?.showLoadingIndicator = true
        }
    }
}
