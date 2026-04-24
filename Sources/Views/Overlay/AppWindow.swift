@preconcurrency import AVFoundation
import AppKit
import Domain
import Presenters
import SwiftUI

@MainActor
protocol OverlayWindowSurface: AnyObject {
    var level: NSWindow.Level { get set }
    var overlayBackgroundColor: NSColor? { get set }
    var isOpaque: Bool { get set }
    var ignoresMouseEvents: Bool { get set }
    var collectionBehavior: NSWindow.CollectionBehavior { get set }
    var contentView: NSView? { get set }
    var frame: NSRect { get }
    func setFrame(_ frameRect: NSRect, display flag: Bool)
    func orderFront(_ sender: Any?)
}

@MainActor
public final class AppWindow: NSWindow {
    static var overlayLevel: NSWindow.Level {
        .init(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    }

    static var overlayCollectionBehavior: NSWindow.CollectionBehavior {
        [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    static func contentFrame(for windowFrame: CGRect) -> CGRect {
        CGRect(origin: .zero, size: windowFrame.size)
    }

    private let hostingView: NSHostingView<OverlayContentView>

    public init(
        initialLayout: ScreenLayout,
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter
    ) {
        let hostingView = NSHostingView(
            rootView: OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                ripplePresenter: ripplePresenter
            ))
        hostingView.frame = initialLayout.hostingFrame
        self.hostingView = hostingView

        super.init(
            contentRect: initialLayout.windowFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        Self.applyOverlayStyle(to: self, hostingView: hostingView)
    }

    public func show() {
        Self.present(self)
    }

    public func applyLayout(_ layout: ScreenLayout) {
        Self.apply(layout: layout, to: self, hostingView: hostingView)
    }

    public func attachPlayerLayer(for player: AVPlayer) {
        Self.attachPlayer(player, to: self, hostingView: hostingView)
    }

    public override func close() {
        orderOut(nil)
        super.close()
    }
}

extension AppWindow: OverlayWindowSurface {
    var overlayBackgroundColor: NSColor? {
        get { backgroundColor }
        set { backgroundColor = newValue }
    }
}

extension AppWindow {
    static func applyOverlayStyle(to surface: OverlayWindowSurface, hostingView: NSView) {
        surface.level = overlayLevel
        surface.overlayBackgroundColor = .clear
        surface.isOpaque = false
        surface.ignoresMouseEvents = true
        surface.collectionBehavior = overlayCollectionBehavior
        surface.contentView = hostingView
    }

    static func present(_ surface: OverlayWindowSurface) {
        surface.orderFront(nil)
    }

    static func apply(layout: ScreenLayout, to surface: OverlayWindowSurface, hostingView: NSView) {
        surface.setFrame(layout.windowFrame, display: false)
        hostingView.frame = layout.hostingFrame
        if let containerView = surface.contentView, containerView !== hostingView {
            containerView.frame = CGRect(origin: .zero, size: layout.windowFrame.size)
        }
    }

    static func attachPlayer(
        _ player: AVPlayer,
        to surface: OverlayWindowSurface,
        hostingView: NSView
    ) {
        surface.overlayBackgroundColor = .black

        let containerView = NSView(frame: contentFrame(for: surface.frame))
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = containerView.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.videoGravity = .resizeAspectFill
        containerView.wantsLayer = true
        containerView.layer?.addSublayer(playerLayer)
        containerView.addSubview(hostingView)
        surface.contentView = containerView
    }
}
