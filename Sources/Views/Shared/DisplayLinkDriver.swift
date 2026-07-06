import AppKit
import QuartzCore

@MainActor
public final class DisplayLinkDriver {
    private var displayLink: CADisplayLink?
    private let onFrame: @MainActor (_ frameInterval: Double) -> Void

    public init(onFrame: @escaping @MainActor (_ frameInterval: Double) -> Void) {
        self.onFrame = onFrame
    }

    public func start(in window: NSWindow) {
        let dl = window.displayLink(target: self, selector: #selector(tick))
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc func tick(_ link: CADisplayLink) {
        // `targetTimestamp - timestamp` is the display's expected seconds per
        // frame for this cycle — stable per display mode and correct for
        // 120 Hz ProMotion / variable refresh, unlike a hardcoded 1/60 (#299).
        onFrame(link.targetTimestamp - link.timestamp)
    }
}
