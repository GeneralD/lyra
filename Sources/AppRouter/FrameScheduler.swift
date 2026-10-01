import AppKit
import Views

@MainActor
protocol FrameScheduler: AnyObject {
    func start(in window: any OverlayWindow)
    func stop()
    /// Suspends per-frame delivery without tearing the scheduler down (#355).
    func pause()
    /// Resumes per-frame delivery after `pause()` (#355).
    func resume()
}

extension DisplayLinkDriver: FrameScheduler {
    func start(in window: any OverlayWindow) {
        guard let window = window as? NSWindow else {
            assertionFailure("DisplayLinkDriver requires an NSWindow-backed OverlayWindow")
            return
        }
        start(in: window)
    }
}
