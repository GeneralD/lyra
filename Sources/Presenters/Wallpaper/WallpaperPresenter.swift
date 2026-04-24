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

    private var items: [ResolvedWallpaperItem] = []
    private var mode: WallpaperPlaybackMode = .cycle
    private var currentIndex: Int = 0

    private var loopObserver: NSObjectProtocol?
    private var endTimeObserver: Any?
    private var isSeeking: Bool = false
    private var loadTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.wallpaperInteractor) private var interactor
    @Dependency(\.randomSource) private var randomSource

    public init() {}

    public func start() {
        loadTask?.cancel()
        isLoading = true
        items = []
        currentIndex = 0
        mode = interactor.playbackMode
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
        tearDownPlayer()
        cancellables.removeAll()
        items = []
        currentIndex = 0
    }

    /// Register a side-effect to run the first time a player becomes available.
    /// The wireframe uses this to drive `OverlayWindow.attachPlayerLayer` without
    /// owning the subscription.
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
            player = nil
            return
        }
        let item = items[currentIndex]
        wallpaperURL = item.url
        startTime = item.start
        endTime = item.end
        await setupPlayer(for: item)
        if cancellables.isEmpty {
            observeSleepWake()
        }
    }

    private func setupPlayer(for item: ResolvedWallpaperItem) async {
        let player = AVPlayer(url: item.url)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
        self.player = player

        let seekStart = item.start.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .zero
        let seekEnd = item.end.map { CMTime(seconds: $0, preferredTimescale: 600) }

        if seekStart != .zero {
            await player.seek(to: seekStart, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if let seekEnd {
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            endTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
                Task { @MainActor in self?.handleLoopBoundary(at: time, seekEnd: seekEnd, seekStart: seekStart, player: player) }
            }
        }

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleItemCompletion(seekStart: seekStart) }
        }

        player.play()
    }

    private func tearDownPlayer() {
        player?.pause()
        endTimeObserver.map { player?.removeTimeObserver($0) }
        loopObserver.map(NotificationCenter.default.removeObserver)
        endTimeObserver = nil
        loopObserver = nil
        isSeeking = false
        player = nil
    }

    private func observeSleepWake() {
        interactor.systemSleepChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                switch event {
                case .willSleep: self?.player?.pause()
                case .didWake: self?.player?.play()
                }
            }
            .store(in: &cancellables)
    }

    func waitForLoad() async {
        await loadTask?.value
    }

    func handleLoopBoundary(at time: CMTime, seekEnd: CMTime, seekStart: CMTime, player: AVPlayer?) {
        guard !isSeeking, time >= seekEnd else { return }
        guard items.count <= 1 else {
            Task { @MainActor [weak self] in await self?.advanceToNextItem() }
            return
        }
        isSeeking = true
        player?.seek(to: seekStart, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.isSeeking = false }
        }
    }

    func handleItemCompletion(seekStart: CMTime) async {
        guard items.count > 1 else {
            Self.restartPlayback(from: seekStart, player: player)
            return
        }
        await advanceToNextItem()
    }

    func advanceToNextItem() async {
        guard items.count > 1 else { return }
        currentIndex = nextIndex(from: currentIndex)
        tearDownPlayer()
        await activateCurrentItem()
    }

    func nextIndex(from current: Int) -> Int {
        switch mode {
        case .cycle:
            return (current + 1) % items.count
        case .shuffle:
            let candidates = (0..<items.count).filter { $0 != current }
            guard !candidates.isEmpty else { return current }
            return candidates[randomSource.next(below: candidates.count)]
        }
    }

    static func restartPlayback(from seekStart: CMTime, player: AVPlayer?) {
        player?.seek(to: seekStart, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
    }
}
