import AppKit
import AVFoundation
import BackdropConfig
import BackdropDomain
import BackdropLyrics
import BackdropNowPlaying
import BackdropUI
import Dependencies
import SwiftUI

@MainActor
public final class OverlayWindow {
    private let window: NSWindow
    private let state = OverlayState()
    private let rippleState = RippleState()
    private let lyricsService = LyricsService()
    private var displayLinkDriver: DisplayLinkDriver?
    private var loopObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private let hostingView: NSHostingView<OverlayContentView>
    private let hasWallpaper: Bool
    private var lastTrackKey: (String?, String?) = (nil, nil)
    private var latestNowPlaying: NowPlaying?
    private var queuePlayer: AVPlayer?
    private var nowPlayingTask: Task<Void, Never>?

    @Dependency(\.config) private var resolvedConfig
    @Dependency(\.nowPlayingProvider) private var nowPlayingProvider

    public init() {
        @Dependency(\.config) var cfg

        hasWallpaper = cfg.wallpaperURL != nil

        let frames = Self.resolveFrames(
            selector: cfg.screen,
            wallpaperURL: cfg.wallpaperURL,
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

        state.screenOrigin = frames.origin
        let hostingView = NSHostingView(rootView: OverlayContentView(
            state: state,
            rippleState: rippleState
        ))
        hostingView.frame = frames.hosting
        self.hostingView = hostingView

        if let wallpaperURL = cfg.wallpaperURL {
            let containerView = NSView(frame: NSRect(origin: .zero, size: frames.window.size))
            let player = AVPlayer(url: wallpaperURL)
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.actionAtItemEnd = .none
            queuePlayer = player

            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem, queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
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
            self?.updateUI()
        }
        self.displayLinkDriver = driver

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [rippleState] event in
            rippleState.update(screenPoint: NSEvent.mouseLocation)
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recalculateLayout() }
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

    public func start() {
        nowPlayingTask = Task { [weak self] in
            guard let self else { return }
            for await info in nowPlayingProvider.stream() {
                guard !Task.isCancelled else { break }
                if let info {
                    latestNowPlaying = info
                    updateTrack(from: info)
                    updateActiveLineIndex(from: info)
                } else {
                    clearIfNeeded()
                }
            }
        }
    }

    private func recalculateLayout() {
        let cfg = resolvedConfig
        let frames = Self.resolveFrames(
            selector: cfg.screen,
            wallpaperURL: cfg.wallpaperURL,
            hasWallpaper: hasWallpaper
        )
        window.setFrame(frames.window, display: false)
        state.screenOrigin = frames.origin
        hostingView.frame = frames.hosting
        if let containerView = window.contentView, containerView !== hostingView {
            containerView.frame = NSRect(origin: .zero, size: frames.window.size)
        }
    }

    private func updateUI() {
        rippleState.idle()
        guard let info = latestNowPlaying else { return }
        updateActiveLineIndex(from: info)
    }

    private func clearIfNeeded() {
        guard lastTrackKey != (nil, nil) else { return }
        lastTrackKey = (nil, nil)
        state.reset()
    }

    private func updateTrack(from info: NowPlaying) {
        if info.artworkData != state.artworkData { state.artworkData = info.artworkData }

        let trackKey = (info.title, info.artist)
        guard trackKey != lastTrackKey else { return }

        lastTrackKey = trackKey
        state.title = info.title
        state.artist = info.artist
        state.activeLineIndex = nil
        state.fetchGeneration += 1
        let generation = state.fetchGeneration

        let service = lyricsService
        Task {
            let result: LyricsResult? = await {
                guard let title = info.title, let artist = info.artist else { return nil }
                return await service.fetch(title: title, artist: artist, duration: info.duration)
            }()
            let content = LyricsContent(from: result)
            guard generation == state.fetchGeneration else { return }
            state.title = result?.trackName ?? info.title
            state.artist = result?.artistName ?? info.artist
            state.lyrics = content
            state.activeLineIndex = nil
        }
    }

    private func updateActiveLineIndex(from info: NowPlaying) {
        guard case let .timed(lines) = state.lyrics else { return }
        let index = info.elapsed.flatMap { elapsed in lines.lastIndex { $0.time <= elapsed } }
        guard index != state.activeLineIndex else { return }
        state.activeLineIndex = index
    }

    public func close() {
        nowPlayingTask?.cancel()
        displayLinkDriver?.stop()
        queuePlayer?.pause()
        loopObserver.map(NotificationCenter.default.removeObserver)
        mouseMonitor.map(NSEvent.removeMonitor)
        screenObserver.map(NotificationCenter.default.removeObserver)
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver.map(ws.removeObserver)
        wakeObserver.map(ws.removeObserver)
        window.orderOut(nil)
        window.close()
    }

    // MARK: - Screen resolution

    private static func resolveFrames(
        selector: ScreenSelector,
        wallpaperURL: URL?,
        hasWallpaper: Bool
    ) -> (window: NSRect, hosting: NSRect, origin: CGPoint) {
        let screen = resolveScreen(selector: selector, wallpaperURL: wallpaperURL)
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        let windowRect = hasWallpaper ? fullFrame : visibleFrame
        let hostingFrame = NSRect(
            x: visibleFrame.minX - windowRect.minX,
            y: visibleFrame.minY - windowRect.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        return (windowRect, hostingFrame, CGPoint(x: visibleFrame.minX, y: visibleFrame.minY))
    }

    private static func resolveScreen(selector: ScreenSelector, wallpaperURL: URL?) -> NSScreen {
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
            guard let track = asset.tracks(withMediaType: .video).first else { return .main ?? screens[0] }
            let size = track.naturalSize.applying(track.preferredTransform)
            let videoAspect = abs(size.width) / abs(size.height)
            return screens.min { a, b in
                let aa = a.frame.width / a.frame.height
                let ba = b.frame.width / b.frame.height
                return abs(aa - videoAspect) < abs(ba - videoAspect)
            } ?? screens[0]
        }
    }
}
