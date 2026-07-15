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

/// The main overlay window for the application.
///
/// It is a borderless `NSWindow` that covers the entire screen (or a specific area)
/// and hosts the SwiftUI overlay content. It handles geometry reconciliation,
/// wallpaper scaling, and AVPlayerLayer attachment.
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

    /// Initializes the app window with the specified layout and presenters.
    ///
    /// - Parameters:
    ///   - initialLayout: The initial geometry for the window and hosting view.
    ///   - headerPresenter: Presenter for the header view.
    ///   - lyricsPresenter: Presenter for the lyrics view.
    ///   - ripplePresenter: Presenter for the ripple effect.
    ///   - spectrumPresenter: Presenter for the spectrum analyzer bars.
    ///   - wallpaperPresenter: Presenter for the wallpaper view.
    ///   - configStatusPresenter: Presenter for the config-error indicator overlay.
    public init(
        initialLayout: ScreenLayout,
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter,
        spectrumPresenter: SpectrumPresenter,
        wallpaperPresenter: WallpaperPresenter,
        configStatusPresenter: ConfigStatusPresenter? = nil
    ) {
        let hostingView = NSHostingView(
            rootView: OverlayContentView(
                headerPresenter: headerPresenter,
                lyricsPresenter: lyricsPresenter,
                ripplePresenter: ripplePresenter,
                spectrumPresenter: spectrumPresenter,
                wallpaperPresenter: wallpaperPresenter,
                configStatusPresenter: configStatusPresenter
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

    /// Brings the window to the front.
    public func show() {
        Self.present(self)
    }

    /// Updates the window and hosting view geometry.
    ///
    /// - Parameter layout: The new layout to apply.
    public func applyLayout(_ layout: ScreenLayout) {
        Self.apply(layout: layout, to: self, hostingView: hostingView)
    }

    /// Attaches an `AVPlayer` layer to the window for wallpaper playback.
    ///
    /// - Parameter player: The player to attach.
    public func attachPlayerLayer(for player: AVPlayer) {
        Self.attachPlayer(player, to: self, hostingView: hostingView)
    }

    /// Applies an affine transform scale to the wallpaper player layer.
    ///
    /// - Parameter scale: The scale factor to apply.
    public func applyWallpaperScale(_ scale: Double) {
        Self.applyWallpaperScale(scale, to: self)
    }

    /// Hides the window and calls the superclass `close`.
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
        applyFrame(layout.hostingFrame, to: hostingView)
        guard let containerView = surface.contentView, containerView !== hostingView else { return }
        applyFrame(contentFrame(for: layout.windowFrame), to: containerView)
        guard let playerLayer = playerLayer(in: surface) else { return }
        reassertGeometry(of: playerLayer, in: containerView.bounds)
    }

    private static func applyWindowFrame(_ frame: NSRect, to surface: OverlayWindowSurface) {
        guard surface.frame != frame else { return }
        surface.setFrame(frame, display: false)
    }

    private static func applyFrame(_ frame: CGRect, to view: NSView) {
        guard view.frame != frame else { return }
        view.frame = frame
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
