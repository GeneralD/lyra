@preconcurrency import AVFoundation
import AppKit
import Dependencies
import Domain
import Presentation
import SwiftUI
import Views

@MainActor
final class AppWindow: NSWindow {
    private let hostingView: NSHostingView<OverlayContentView>
    private var screenObserver: NSObjectProtocol?

    @Dependency(\.screenInteractor) private var screenInteractor

    init(
        wallpaperPresenter: WallpaperPresenter,
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter
    ) {
        @Dependency(\.screenInteractor) var screen
        let layout = screen.resolveLayout()

        let hostingView = NSHostingView(
            rootView: OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                rippleState: ripplePresenter.rippleState ?? RippleState(),
                screenOrigin: layout.screenOrigin,
                rippleConfig: ripplePresenter.rippleConfig
            ))
        hostingView.frame = layout.hostingFrame
        self.hostingView = hostingView

        super.init(
            contentRect: layout.windowFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        backgroundColor = wallpaperPresenter.player != nil ? .black : .clear
        isOpaque = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        if let player = wallpaperPresenter.player {
            let containerView = NSView(frame: CGRect(origin: .zero, size: layout.windowFrame.size))
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
            self?.recalculateLayout()
        }
    }

    deinit {
        screenObserver.map(NotificationCenter.default.removeObserver)
    }

    private func recalculateLayout() {
        let layout = screenInteractor.resolveLayout()
        setFrame(layout.windowFrame, display: false)
        hostingView.frame = layout.hostingFrame
        if let containerView = contentView, containerView !== hostingView {
            containerView.frame = CGRect(origin: .zero, size: layout.windowFrame.size)
        }
    }
}
