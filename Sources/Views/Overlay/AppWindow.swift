@preconcurrency import AVFoundation
import AppKit
import Combine
import Domain
import Presenters
import SwiftUI

@MainActor
public final class AppWindow: NSWindow {
    private let hostingView: NSHostingView<OverlayContentView>
    private let appPresenter: AppPresenter
    private var screenObserver: NSObjectProtocol?
    private var playerCancellable: AnyCancellable?

    public init(
        appPresenter: AppPresenter,
        wallpaperPresenter: WallpaperPresenter,
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter
    ) {
        self.appPresenter = appPresenter
        let layout = appPresenter.layout

        let hostingView = NSHostingView(
            rootView: OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                ripplePresenter: ripplePresenter
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
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        contentView = hostingView

        // When player becomes available (async wallpaper DL or cached), attach AVPlayerLayer
        playerCancellable = wallpaperPresenter.$player
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] player in
                self?.attachPlayer(player)
            }

        orderFront(nil)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recalculateLayout() }
        }
    }

    deinit {
        screenObserver.map(NotificationCenter.default.removeObserver)
    }

    private func attachPlayer(_ player: AVPlayer) {
        let layout = appPresenter.layout
        backgroundColor = .black

        let containerView = NSView(frame: CGRect(origin: .zero, size: layout.windowFrame.size))
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = containerView.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.videoGravity = .resizeAspectFill
        containerView.wantsLayer = true
        containerView.layer?.addSublayer(playerLayer)
        containerView.addSubview(hostingView)
        contentView = containerView
    }

    private func recalculateLayout() {
        appPresenter.recalculateLayout()
        let layout = appPresenter.layout
        setFrame(layout.windowFrame, display: false)
        hostingView.frame = layout.hostingFrame
        if let containerView = contentView, containerView !== hostingView {
            containerView.frame = CGRect(origin: .zero, size: layout.windowFrame.size)
        }
    }
}
