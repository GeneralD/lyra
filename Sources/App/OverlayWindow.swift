@preconcurrency import AVFoundation
import AppKit
import Dependencies
import Domain
import Presentation
import SwiftUI
import Views

@MainActor
public final class OverlayWindow {
    private let window: NSWindow
    private let hostingView: NSHostingView<OverlayContentView>
    private let hasWallpaper: Bool
    private let lyricsPresenter: LyricsPresenter
    private let ripplePresenter: RipplePresenter
    private var displayLinkDriver: DisplayLinkDriver?
    private var loopObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var queuePlayer: AVPlayer?
    private var endTimeObserver: Any?

    public init(
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter,
        wallpaperPresenter: WallpaperPresenter
    ) async {
        self.lyricsPresenter = lyricsPresenter
        self.ripplePresenter = ripplePresenter

        let wallpaperURL = wallpaperPresenter.wallpaperURL
        hasWallpaper = wallpaperURL != nil

        @Dependency(\.configUseCase) var configService
        let appStyle = configService.loadAppStyle()

        let frames = await Self.resolveFrames(
            selector: appStyle.screen,
            wallpaperURL: wallpaperURL,
            hasWallpaper: hasWallpaper
        )

        let window = NSWindow(
            contentRect: frames.window,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.backgroundColor = hasWallpaper ? .black : .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rippleState = RippleState()
        let hostingView = NSHostingView(
            rootView: OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                rippleState: rippleState,
                screenOrigin: frames.origin
            ))
        hostingView.frame = frames.hosting
        self.hostingView = hostingView

        if let wallpaperURL {
            let containerView = NSView(frame: CGRect(origin: .zero, size: frames.window.size))
            let player = AVPlayer(url: wallpaperURL)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.actionAtItemEnd = .none
            queuePlayer = player

            let startTime = wallpaperPresenter.start.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .zero
            let endTime = wallpaperPresenter.end.map { CMTime(seconds: $0, preferredTimescale: 600) }

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

            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = containerView.bounds
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            playerLayer.videoGravity = .resizeAspectFill
            containerView.wantsLayer = true
            containerView.layer?.addSublayer(playerLayer)

            containerView.addSubview(hostingView)
            window.contentView = containerView
            player.play()
        } else {
            window.contentView = hostingView
        }

        self.window = window
        window.orderFront(nil)

        let driver = DisplayLinkDriver { [weak self] in
            self?.ripplePresenter.idle()
            self?.lyricsPresenter.updateActiveLineTick()
        }
        self.displayLinkDriver = driver

        if ripplePresenter.isEnabled {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak ripplePresenter] event in
                ripplePresenter?.update(screenPoint: NSEvent.mouseLocation)
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.recalculateLayout() }
        }

        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.queuePlayer?.pause() }
        }
        wakeObserver = ws.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.queuePlayer?.play() }
        }

        driver.start(in: window)
    }

    public func close() {
        displayLinkDriver?.stop()
        queuePlayer?.pause()
        endTimeObserver.map { queuePlayer?.removeTimeObserver($0) }
        loopObserver.map(NotificationCenter.default.removeObserver)
        mouseMonitor.map(NSEvent.removeMonitor)
        screenObserver.map(NotificationCenter.default.removeObserver)
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver.map(ws.removeObserver)
        wakeObserver.map(ws.removeObserver)
        window.orderOut(nil)
        window.close()
    }

    private func recalculateLayout() async {
        @Dependency(\.configUseCase) var configService
        let appStyle = configService.loadAppStyle()
        let frames = await Self.resolveFrames(
            selector: appStyle.screen,
            wallpaperURL: queuePlayer?.currentItem?.asset as? AVURLAsset != nil
                ? (queuePlayer?.currentItem?.asset as? AVURLAsset)?.url : nil,
            hasWallpaper: hasWallpaper
        )
        window.setFrame(frames.window, display: false)
        hostingView.frame = frames.hosting
        if let containerView = window.contentView, containerView !== hostingView {
            containerView.frame = CGRect(origin: .zero, size: frames.window.size)
        }
    }

    // MARK: - Screen resolution

    private static func resolveFrames(
        selector: ScreenSelector,
        wallpaperURL: URL?,
        hasWallpaper: Bool
    ) async -> (window: CGRect, hosting: CGRect, origin: CGPoint) {
        let screen = await resolveScreen(selector: selector, wallpaperURL: wallpaperURL)
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        let windowRect = hasWallpaper ? fullFrame : visibleFrame
        let hostingFrame = CGRect(
            x: visibleFrame.minX - windowRect.minX,
            y: visibleFrame.minY - windowRect.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        return (windowRect, hostingFrame, CGPoint(x: visibleFrame.minX, y: visibleFrame.minY))
    }

    private static func resolveScreen(selector: ScreenSelector, wallpaperURL: URL?) async -> NSScreen {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main ?? NSScreen() }
        switch selector {
        case .main:
            return .main ?? screens[0]
        case .primary:
            return screens[0]
        case .index(let n):
            return n < screens.count ? screens[n] : screens[0]
        case .smallest:
            return screens.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height } ?? screens[0]
        case .largest:
            return screens.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height } ?? screens[0]
        case .match:
            guard let url = wallpaperURL else { return .main ?? screens[0] }
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return .main ?? screens[0] }
            let naturalSize = try? await track.load(.naturalSize)
            let transform = try? await track.load(.preferredTransform)
            guard let naturalSize, let transform else { return .main ?? screens[0] }
            let size = naturalSize.applying(transform)
            let videoAspect = abs(size.width) / abs(size.height)
            return screens.min { a, b in
                let aa = a.frame.width / a.frame.height
                let ba = b.frame.width / b.frame.height
                return abs(aa - videoAspect) < abs(ba - videoAspect)
            } ?? screens[0]
        }
    }
}
