import AppKit
import QuartzCore

@MainActor
public final class DisplayLinkDriver {
    // `private(set)` (rather than `private`) so `@testable import Views` can read
    // the live link back in tests, while only this type can assign it (#355).
    private(set) var displayLink: CADisplayLink?
    private let onFrame: @MainActor (_ frameInterval: Double) -> Void

    public init(onFrame: @escaping @MainActor (_ frameInterval: Double) -> Void) {
        self.onFrame = onFrame
    }

    /// Idempotent: a previously started link is invalidated before the new one
    /// is created, so calling this twice without an intervening `stop()` never
    /// leaks the earlier `CADisplayLink` still firing in the background (#355).
    public func start(in window: NSWindow) {
        displayLink?.invalidate()
        let dl = window.displayLink(target: self, selector: #selector(tick))
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Suspends frame delivery without tearing down the link, so `resume()` can
    /// pick back up without going through `start(in:)` again (#355).
    public func pause() {
        displayLink?.isPaused = true
    }

    public func resume() {
        displayLink?.isPaused = false
    }

    @objc func tick(_ link: CADisplayLink) {
        // `targetTimestamp - timestamp` is the display's expected seconds per
        // frame for this cycle — stable per display mode and correct for
        // 120 Hz ProMotion / variable refresh, unlike a hardcoded 1/60 (#299).
        onFrame(link.targetTimestamp - link.timestamp)
    }
}
