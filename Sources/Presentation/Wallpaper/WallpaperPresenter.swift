@preconcurrency import AVFoundation
import Dependencies
import Domain
import Foundation

@MainActor
public final class WallpaperPresenter: ObservableObject {
    @Published public private(set) var wallpaperURL: URL?
    @Published public private(set) var start: TimeInterval?
    @Published public private(set) var end: TimeInterval?
    @Published public private(set) var isLoading: Bool = false

    public private(set) var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var endTimeObserver: Any?

    @Dependency(\.wallpaperInteractor) private var interactor

    public init() {}

    public func resolve() async {
        isLoading = true
        let state = try? await interactor.resolveWallpaper()
        wallpaperURL = state?.url
        start = state?.start
        end = state?.end
        isLoading = false
    }

    public func setupPlayer() async {
        guard let wallpaperURL else { return }

        let player = AVPlayer(url: wallpaperURL)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
        self.player = player

        let startTime = start.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .zero
        let endTime = end.map { CMTime(seconds: $0, preferredTimescale: 600) }

        if startTime != .zero {
            await player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if let endTime {
            var seeking = false
            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            endTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
                guard !seeking, time >= endTime else { return }
                seeking = true
                player?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    seeking = false
                }
            }
        }

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { [weak player] _ in
            player?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
            player?.play()
        }

        player.play()
    }

    public func pause() { player?.pause() }
    public func play() { player?.play() }

    public func stop() {
        player?.pause()
        endTimeObserver.map { player?.removeTimeObserver($0) }
        loopObserver.map(NotificationCenter.default.removeObserver)
        player = nil
    }
}
