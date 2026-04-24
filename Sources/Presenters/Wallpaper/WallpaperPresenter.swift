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

    private var loopObserver: NSObjectProtocol?
    private var endTimeObserver: Any?
    private var isSeeking: Bool = false
    private var loadTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    @Dependency(\.wallpaperInteractor) private var interactor

    public init() {}

    public func start() {
        loadTask?.cancel()
        isLoading = true
        let interactor = self.interactor
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let state = try? await interactor.resolveWallpaper()
            wallpaperURL = state?.url
            startTime = state?.start
            endTime = state?.end
            isLoading = false
            await setupPlayer()
        }
    }

    public func stop() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        endTimeObserver.map { player?.removeTimeObserver($0) }
        loopObserver.map(NotificationCenter.default.removeObserver)
        endTimeObserver = nil
        loopObserver = nil
        cancellables.removeAll()
        player = nil
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
    private func setupPlayer() async {
        guard let wallpaperURL else { return }

        let player = AVPlayer(url: wallpaperURL)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
        self.player = player

        let seekStart = startTime.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .zero
        let seekEnd = endTime.map { CMTime(seconds: $0, preferredTimescale: 600) }

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
        ) { [weak player] _ in
            Task { @MainActor in
                Self.restartPlayback(from: seekStart, player: player)
            }
        }

        player.play()
        observeSleepWake()
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
        isSeeking = true
        player?.seek(to: seekStart, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.isSeeking = false }
        }
    }

    static func restartPlayback(from seekStart: CMTime, player: AVPlayer?) {
        player?.seek(to: seekStart, toleranceBefore: .zero, toleranceAfter: .zero)
        player?.play()
    }
}
