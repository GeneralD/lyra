@preconcurrency import AVFoundation
import AppKit
import Domain
import Presentation
import SwiftUI
import Views

@MainActor
final class AppWindow: NSWindow {
    private let hostingView: NSHostingView<OverlayContentView>
    private let appPresenter: AppPresenter
    private var screenObserver: NSObjectProtocol?

    init(
        appPresenter: AppPresenter,
        wallpaperPresenter: WallpaperPresenter,
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter
    ) {
        self.appPresenter = appPresenter

        let hostingView = NSHostingView(
            rootView: OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                rippleState: ripplePresenter.rippleState ?? RippleState(),
                screenOrigin: appPresenter.layout.screenOrigin,
                rippleConfig: ripplePresenter.rippleConfig
            ))
        hostingView.frame = appPresenter.layout.hostingFrame
        self.hostingView = hostingView

        super.init(
            contentRect: appPresenter.layout.windowFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        backgroundColor = appPresenter.hasWallpaper ? .black : .clear
        isOpaque = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        if let player = wallpaperPresenter.player {
            let containerView = NSView(frame: CGRect(origin: .zero, size: appPresenter.layout.windowFrame.size))
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = containerView.bounds
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            playerLayer.videoGravity = .resizeAspectFill
            containerView.wantsLayer = true
            containerView.layer?.addSublayer(playerLayer)
            containerView.addSubview(hostingView)
            contentView = containerView
        } else {
            contentView = hostingView
        }

        orderFront(nil)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.recalculateLayout() }
        }
    }

    deinit {
        screenObserver.map(NotificationCenter.default.removeObserver)
    }

    private func recalculateLayout() async {
        await appPresenter.resolveFrames()
        let layout = appPresenter.layout
        setFrame(layout.windowFrame, display: false)
        hostingView.frame = layout.hostingFrame
        if let containerView = contentView, containerView !== hostingView {
            containerView.frame = CGRect(origin: .zero, size: layout.windowFrame.size)
        }
    }
}
