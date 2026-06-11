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
        ripplePresenter: RipplePresenter,
        wallpaperPresenter: WallpaperPresenter
    ) {
        let hostingView = NSHostingView(
            rootView: OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                ripplePresenter: ripplePresenter,
                wallpaperPresenter: wallpaperPresenter
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

    public func applyWallpaperScale(_ scale: Double) {
        Self.applyWallpaperScale(scale, to: self)
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

    /// Re-asserts the full window/view/layer geometry from the resolved layout.
    /// Idempotent by design: the window server mutates the actual window during
    /// display reconfiguration (#265), so every call reconciles against actual
    /// state instead of trusting that earlier applications are still in effect.
    /// Skipping `setFrame` when the frame already matches keeps the
    /// `NSWindow.didMove/didResize → screenChanges → apply` cycle from looping.
    static func apply(layout: ScreenLayout, to surface: OverlayWindowSurface, hostingView: NSView) {
        applyWindowFrame(layout.windowFrame, to: surface)
        hostingView.frame = layout.hostingFrame
        guard let containerView = surface.contentView, containerView !== hostingView else { return }
        containerView.frame = CGRect(origin: .zero, size: layout.windowFrame.size)
        guard let playerLayer = playerLayer(in: surface) else { return }
        reassertGeometry(of: playerLayer, in: containerView.bounds)
    }

    private static func applyWindowFrame(_ frame: NSRect, to surface: OverlayWindowSurface) {
        guard surface.frame != frame else { return }
        surface.setFrame(frame, display: false)
    }

    /// Sets `bounds` + `position` rather than `frame`: the layer carries the
    /// wallpaper-scale affine transform, and `frame` is undefined under a
    /// non-identity transform.
    private static func reassertGeometry(of playerLayer: AVPlayerLayer, in bounds: CGRect) {
        playerLayer.bounds = bounds
        playerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    static func attachPlayer(
        _ player: AVPlayer,
        to surface: OverlayWindowSurface,
        hostingView: NSView,
        scale: Double = 1.0
    ) {
        surface.overlayBackgroundColor = .black

        let containerView = NSView(frame: contentFrame(for: surface.frame))
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = containerView.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.videoGravity = .resizeAspectFill
        applyWallpaperScale(scale, to: playerLayer)
        containerView.wantsLayer = true
        containerView.layer?.addSublayer(playerLayer)
        containerView.addSubview(hostingView)
        surface.contentView = containerView
    }

    static func applyWallpaperScale(_ scale: Double, to surface: OverlayWindowSurface) {
        guard let playerLayer = playerLayer(in: surface) else { return }
        applyWallpaperScale(scale, to: playerLayer)
    }

    static func sanitizedWallpaperScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1.0 }
        return max(1.0, scale)
    }

    private static func applyWallpaperScale(_ scale: Double, to playerLayer: AVPlayerLayer) {
        let sanitizedScale = sanitizedWallpaperScale(scale)
        playerLayer.setAffineTransform(
            CGAffineTransform(scaleX: sanitizedScale, y: sanitizedScale))
    }

    private static func playerLayer(in surface: OverlayWindowSurface) -> AVPlayerLayer? {
        surface.contentView?.layer?.sublayers?.compactMap { $0 as? AVPlayerLayer }.first
    }
}
