@preconcurrency import AVFoundation
import AppKit
import Dependencies
import Domain
import Presentation
import SwiftUI
import Views

/// Wireframe and coordination: creates Presenters, subscribes to Interactors,
/// dispatches updates, and manages the overlay window lifecycle.
@MainActor
public final class AppRouter {
    private let headerPresenter = HeaderPresenter()
    private let lyricsPresenter = LyricsPresenter()
    private let wallpaperPresenter = WallpaperPresenter()
    private let ripplePresenter = RipplePresenter()
    private let appPresenter = AppPresenter()

    private var window: NSWindow?
    private var displayLinkDriver: DisplayLinkDriver?
    private var mouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    public init() {}

    public func start() async {
        // Start Presenters
        headerPresenter.start()
        lyricsPresenter.start()
        ripplePresenter.start()

        // Resolve wallpaper
        await wallpaperPresenter.resolve()

        // Resolve screen layout
        await appPresenter.resolveFrames(wallpaperURL: wallpaperPresenter.wallpaperURL)

        // Setup AVPlayer
        await wallpaperPresenter.setupPlayer()

        // Create window
        let window = createWindow()
        self.window = window

        // Setup display link
        let driver = DisplayLinkDriver { [weak self] in
            self?.ripplePresenter.idle()
            self?.lyricsPresenter.updateActiveLineTick()
        }
        self.displayLinkDriver = driver

        // Mouse monitoring for ripple
        if ripplePresenter.isEnabled {
            let rippleState = (window.contentView as? NSHostingView<OverlayContentView>)
                .flatMap { _ in self.rippleState }
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak rippleState] event in
                rippleState?.update(screenPoint: NSEvent.mouseLocation)
            }
        }

        // Screen change observer
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.recalculateLayout() }
        }

        // Sleep/wake observers
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.wallpaperPresenter.pause() }
        }
        wakeObserver = ws.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.wallpaperPresenter.play() }
        }

        driver.start(in: window)
    }

    public func stop() {
        headerPresenter.stop()
        lyricsPresenter.stop()
        wallpaperPresenter.stop()
        displayLinkDriver?.stop()
        mouseMonitor.map(NSEvent.removeMonitor)
        screenObserver.map(NotificationCenter.default.removeObserver)
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver.map(ws.removeObserver)
        wakeObserver.map(ws.removeObserver)
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    // MARK: - Private

    private var rippleState: RippleState?

    private func createWindow() -> NSWindow {
        let rippleConfig = ripplePresenter.interactorRippleConfig
        let rippleState = RippleState(config: rippleConfig)
        self.rippleState = rippleState

        let hostingView = NSHostingView(
            rootView: OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                rippleState: rippleState,
                screenOrigin: appPresenter.layout.screenOrigin,
                rippleConfig: rippleConfig
            ))
        hostingView.frame = appPresenter.layout.hostingFrame

        let window = NSWindow(
            contentRect: appPresenter.layout.windowFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.backgroundColor = appPresenter.hasWallpaper ? .black : .clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        if let player = wallpaperPresenter.player {
            let containerView = NSView(frame: CGRect(origin: .zero, size: appPresenter.layout.windowFrame.size))
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = containerView.bounds
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            playerLayer.videoGravity = .resizeAspectFill
            containerView.wantsLayer = true
            containerView.layer?.addSublayer(playerLayer)
            containerView.addSubview(hostingView)
            window.contentView = containerView
        } else {
            window.contentView = hostingView
        }

        window.orderFront(nil)
        return window
    }

    private func recalculateLayout() async {
        let wallpaperURL = wallpaperPresenter.wallpaperURL
        await appPresenter.resolveFrames(wallpaperURL: wallpaperURL)
        window?.setFrame(appPresenter.layout.windowFrame, display: false)
        if let hostingView = window?.contentView?.subviews.first as? NSHostingView<OverlayContentView> {
            hostingView.frame = appPresenter.layout.hostingFrame
        } else if let hostingView = window?.contentView as? NSHostingView<OverlayContentView> {
            hostingView.frame = appPresenter.layout.hostingFrame
        }
        if let containerView = window?.contentView,
            !(containerView is NSHostingView<OverlayContentView>)
        {
            containerView.frame = CGRect(origin: .zero, size: appPresenter.layout.windowFrame.size)
        }
    }
}
