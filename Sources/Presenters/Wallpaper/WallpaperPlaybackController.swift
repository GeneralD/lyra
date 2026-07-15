@preconcurrency import AVFoundation
import Domain
import Foundation

/// Owns the AVPlayer lifecycle for wallpaper playback. The player instance is
/// created lazily on the first `play(item:)` call and reused across item swaps
/// via `replaceCurrentItem`, so AVPlayerLayer attachments stay stable. The
/// controller emits `onAdvanceRequested` on either the periodic end-time
/// boundary or the `AVPlayerItemDidPlayToEndTime` notification, leaving the
/// "advance vs loop" decision to the Presenter.
@MainActor
final class WallpaperPlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer?

    var onAdvanceRequested: (@MainActor () -> Void)?

    private var seekStart: CMTime = .zero
    private var seekEnd: CMTime?
    private var endTimeObserver: Any?
    private var loopObserver: NSObjectProtocol?
    private var isSeeking: Bool = false

    init() {}
}

extension WallpaperPlaybackController {
    func play(item: ResolvedWallpaperItem) async {
        let player = ensurePlayer()

        seekStart = item.start.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .zero
        seekEnd = item.end.map { CMTime(seconds: $0, preferredTimescale: 600) }
        isSeeking = false

        let avItem = AVPlayerItem(url: item.url)
        player.replaceCurrentItem(with: avItem)
        rebindLoopObserver(for: avItem)
        rebindBoundaryObserver(on: player)

        if seekStart != .zero {
            await player.seek(to: seekStart, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
    }

    func loopCurrent() {
        isSeeking = false
        guard let player else { return }
        player.seek(to: seekStart, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    func stop() {
        player?.pause()
        endTimeObserver.map { player?.removeTimeObserver($0) }
        loopObserver.map(NotificationCenter.default.removeObserver)
        endTimeObserver = nil
        loopObserver = nil
        isSeeking = false
        seekStart = .zero
        seekEnd = nil
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    func handleBoundary(at time: CMTime) {
        guard let seekEnd, !isSeeking, time >= seekEnd else { return }
        isSeeking = true
        onAdvanceRequested?()
    }

    func handleItemEnd() {
        guard !isSeeking else { return }
        isSeeking = true
        onAdvanceRequested?()
    }
}

extension WallpaperPlaybackController {
    private func ensurePlayer() -> AVPlayer {
        if let player { return player }
        let player = AVPlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
        self.player = player
        return player
    }

    private func rebindBoundaryObserver(on player: AVPlayer) {
        if let endTimeObserver {
            player.removeTimeObserver(endTimeObserver)
            self.endTimeObserver = nil
        }
        guard seekEnd != nil else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        endTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self, weak player] time in
            Task { @MainActor in
                guard let self, let player, player === self.player else { return }
                self.handleBoundary(at: time)
            }
        }
    }

    private func rebindLoopObserver(for item: AVPlayerItem) {
        loopObserver.map(NotificationCenter.default.removeObserver)
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleItemEnd() }
        }
    }
}
