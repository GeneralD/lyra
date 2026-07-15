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
    /// The wallpaper source last applied. `applyStyle()` diffs the live source
    /// against this so an unrelated config edit never re-resolves (and restarts)
    /// the playing video; only a real source change reloads.
    private var appliedSource: WallpaperStyle?

    let controller = WallpaperPlaybackController()
    private var loadTask: Task<Void, Never>?
    private var indicatorTask: Task<Void, Never>?
    private var sleepWakeCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.wallpaperInteractor) private var interactor
    @Dependency(\.configInteractor) private var configInteractor
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
        observeSleepWake()
        configInteractor.appStyleChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyStyle() }
            .store(in: &cancellables)
        loadWallpapers(source: interactor.wallpaperSource)
    }

    /// Reacts to a config hot-reload ping. Re-resolves the wallpaper only when the
    /// source actually changed, so an unrelated edit leaves the playing video
    /// untouched (no flicker, no restart). A source swap keeps the AVPlayer alive
    /// (`replaceCurrentItem`), so the overlay never blacks out mid-swap.
    private func applyStyle() {
        let source = interactor.wallpaperSource
        guard source != appliedSource else { return }
        loadWallpapers(source: source)
    }

    private func loadWallpapers(source: WallpaperStyle?) {
        loadTask?.cancel()
        setLoading(true)
        items = []
        currentIndex = 0
        wallpaperScale = 1.0
        mode = interactor.playbackMode
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
            // A newer load superseded this one (cancelled): it already reset
            // `items`, so falling through to the empty-cleanup below would clear
            // the still-playing video mid-swap. Bail instead (#41 PR4 review, F9).
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                setLoading(false)
                // A genuine removal (nil source) applies and restores transparency.
                // A configured source that resolved to zero items (transient
                // download failure, or a file created just after the save) is NOT
                // marked applied, so re-saving the same value retries resolution
                // instead of being swallowed by the diff guard (#41 PR4 review, F8).
                if source == nil {
                    appliedSource = nil
                    clearActiveItem()
                }
            } else {
                // Commit the applied source only on a successful resolve.
                appliedSource = source
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

    /// Register a side-effect to run each time a new AVPlayer instance becomes
    /// available (nil → non-nil). The controller reuses one instance across item
    /// swaps, so this fires once per wallpaper *attach*, not per item advance —
    /// the wireframe drives `OverlayWindow.attachPlayerLayer` here. A hot-reload
    /// that removes all wallpaper tears the player down (see `onPlayerCleared`);
    /// a later re-add builds a fresh instance and fires this again to re-attach.
    public func onPlayerAvailable(_ handler: @escaping @MainActor (AVPlayer) -> Void) {
        $player
            .removeDuplicates { $0 === $1 }
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { player in handler(player) }
            .store(in: &cancellables)
    }

    /// Register a side-effect to run when the player is torn down (non-nil → nil),
    /// i.e. a hot-reload removed all wallpaper. The wireframe uses this to detach
    /// the `AVPlayerLayer` and restore the transparent no-wallpaper backing, so the
    /// overlay does not keep a full-screen black surface until restart.
    public func onPlayerCleared(_ handler: @escaping @MainActor () -> Void) {
        $player
            .scan((previous: AVPlayer?.none, cleared: false)) { state, current in
                (previous: current, cleared: state.previous != nil && current == nil)
            }
            .filter(\.cleared)
            .receive(on: DispatchQueue.main)
            .sink { _ in handler() }
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

    /// Clears the published wallpaper state and tears the player down, for a
    /// hot-reload that removes all wallpaper items. Nil-ing the player fires
    /// `onPlayerCleared`, which detaches the layer and restores the transparent
    /// no-wallpaper backing (a kept-alive player would leave a black surface,
    /// #41 PR4 review, F7). A later re-add builds a fresh player and re-attaches.
    private func clearActiveItem() {
        wallpaperURL = nil
        startTime = nil
        endTime = nil
        wallpaperScale = 1.0
        controller.stop()
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
