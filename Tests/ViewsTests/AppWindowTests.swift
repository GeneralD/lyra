@preconcurrency import AVFoundation
import AppKit
import Domain
import Testing

@testable import Views

@MainActor
@Suite("AppWindow")
struct AppWindowTests {
    @Test("overlay defaults expose transparent desktop window styling")
    func overlayDefaults() {
        #expect(AppWindow.overlayLevel.rawValue == Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        #expect(AppWindow.overlayCollectionBehavior.contains(.canJoinAllSpaces))
        #expect(AppWindow.overlayCollectionBehavior.contains(.stationary))
        #expect(AppWindow.overlayCollectionBehavior.contains(.ignoresCycle))
    }

    @Test("content frame matches window size at zero origin")
    func contentFrame() {
        let windowFrame = CGRect(x: 40, y: 30, width: 1024, height: 640)

        #expect(
            AppWindow.contentFrame(for: windowFrame)
                == CGRect(origin: .zero, size: windowFrame.size)
        )
    }

    @Test("content frame handles empty size without crashing")
    func emptyContentFrame() {
        let windowFrame = CGRect(x: 10, y: 20, width: 0, height: 0)

        #expect(AppWindow.contentFrame(for: windowFrame) == .zero)
    }

    @Test("applyOverlayStyle configures transparent overlay chrome and installs hosting view")
    func applyOverlayStyleConfiguresSurface() {
        let surface = SpyOverlayWindowSurface(frame: .zero)
        let hostingView = NSView()

        AppWindow.applyOverlayStyle(to: surface, hostingView: hostingView)

        #expect(surface.level == AppWindow.overlayLevel)
        #expect(surface.overlayBackgroundColor == .clear)
        #expect(surface.isOpaque == false)
        #expect(surface.ignoresMouseEvents)
        #expect(surface.collectionBehavior == AppWindow.overlayCollectionBehavior)
        #expect(surface.contentView === hostingView)
    }

    @Test("present orders the surface to the front once")
    func presentOrdersFront() {
        let surface = SpyOverlayWindowSurface(frame: .zero)

        AppWindow.present(surface)

        #expect(surface.orderFrontCallCount == 1)
    }

    @Test("apply layout updates window frame and hosting frame")
    func applyLayoutUpdatesHostingFrame() {
        let layout = ScreenLayout(
            windowFrame: CGRect(x: 40, y: 30, width: 1024, height: 640),
            hostingFrame: CGRect(x: 24, y: 32, width: 960, height: 576),
            screenOrigin: CGPoint(x: 40, y: 30)
        )
        let hostingView = NSView()
        let surface = SpyOverlayWindowSurface(frame: .zero)
        surface.contentView = hostingView

        AppWindow.apply(layout: layout, to: surface, hostingView: hostingView)

        #expect(surface.setFrameCalls.count == 1)
        #expect(surface.setFrameCalls.last?.0 == layout.windowFrame)
        #expect(surface.setFrameCalls.last?.1 == false)
        #expect(hostingView.frame == layout.hostingFrame)
    }

    @Test("apply layout resizes the player container when content view is not the hosting view")
    func applyLayoutResizesContainer() {
        let layout = ScreenLayout(
            windowFrame: CGRect(x: 0, y: 0, width: 1280, height: 720),
            hostingFrame: CGRect(x: 0, y: 0, width: 1280, height: 720),
            screenOrigin: .zero
        )
        let hostingView = NSView()
        let containerView = NSView(frame: CGRect(x: 10, y: 10, width: 1, height: 1))
        let surface = SpyOverlayWindowSurface(frame: .zero)
        surface.contentView = containerView

        AppWindow.apply(layout: layout, to: surface, hostingView: hostingView)

        #expect(containerView.frame == CGRect(origin: .zero, size: layout.windowFrame.size))
        #expect(hostingView.frame == layout.hostingFrame)
    }

    @Test("attachPlayer wraps hosting view in a player-backed container")
    func attachPlayerWrapsHostingView() {
        let hostingView = NSView()
        let surface = SpyOverlayWindowSurface(
            frame: CGRect(x: 0, y: 0, width: 800, height: 500)
        )
        surface.contentView = hostingView
        let player = AVPlayer()

        AppWindow.attachPlayer(player, to: surface, hostingView: hostingView)

        #expect(surface.overlayBackgroundColor == .black)

        let container = surface.contentView
        #expect(container !== hostingView)
        #expect(container?.frame == CGRect(x: 0, y: 0, width: 800, height: 500))
        #expect(container?.subviews.contains(hostingView) == true)

        let playerLayer = container?.layer?.sublayers?.compactMap { $0 as? AVPlayerLayer }.first
        #expect(playerLayer?.player === player)
        #expect(playerLayer?.videoGravity == .resizeAspectFill)
        #expect(playerLayer?.autoresizingMask == [.layerWidthSizable, .layerHeightSizable])
    }
}

@MainActor
final class SpyOverlayWindowSurface: OverlayWindowSurface {
    var level: NSWindow.Level = .normal
    var overlayBackgroundColor: NSColor?
    var isOpaque: Bool = true
    var ignoresMouseEvents: Bool = false
    var collectionBehavior: NSWindow.CollectionBehavior = []
    var contentView: NSView?
    private(set) var frame: NSRect
    private(set) var setFrameCalls: [(NSRect, Bool)] = []
    private(set) var orderFrontCallCount = 0

    init(frame: NSRect) {
        self.frame = frame
    }

    func setFrame(_ frameRect: NSRect, display flag: Bool) {
        frame = frameRect
        setFrameCalls.append((frameRect, flag))
    }

    func orderFront(_ sender: Any?) {
        orderFrontCallCount += 1
    }
}
