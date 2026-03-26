@preconcurrency import AVFoundation
import AppKit
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
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    @Dependency(\.wallpaperInteractor) private var interactor

    public init() {}

    public func start() {
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            let state = try? await interactor.resolveWallpaper()
            wallpaperURL = state?.url
            startTime = state?.start
            endTime = state?.end
            isLoading = false
            await setupPlayer()
        }
    }

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
            var seeking = false
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            endTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
                guard !seeking, time >= seekEnd else { return }
                seeking = true
                player?.seek(to: seekStart, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    seeking = false
                }
            }
        }

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { [weak player] _ in
            player?.seek(to: seekStart, toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }

        player.play()
        observeSleepWake()
    }

    public func stop() {
        player?.pause()
        endTimeObserver.map { player?.removeTimeObserver($0) }
        loopObserver.map(NotificationCenter.default.removeObserver)
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver.map(ws.removeObserver)
        wakeObserver.map(ws.removeObserver)
        player = nil
    }
}

extension WallpaperPresenter {
    private func observeSleepWake() {
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.pause() }
        }
        wakeObserver = ws.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.play() }
        }
    }
}
