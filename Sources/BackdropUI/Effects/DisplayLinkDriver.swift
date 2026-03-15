import AppKit
import QuartzCore

@MainActor
public final class DisplayLinkDriver {
    private var displayLink: CADisplayLink?
    private let onFrame: @MainActor () -> Void

    public init(onFrame: @escaping @MainActor () -> Void) {
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
        onFrame()
    }
}
