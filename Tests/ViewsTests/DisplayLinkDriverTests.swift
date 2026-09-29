import AppKit
import Testing

@testable import Views

@MainActor
@Suite("DisplayLinkDriver")
struct DisplayLinkDriverTests {
    @Test("tick forwards the display's frame interval to onFrame")
    func tickForwardsFrameInterval() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless], backing: .buffered, defer: false)
        var capturedInterval: Double?
        let driver = DisplayLinkDriver { interval in capturedInterval = interval }
        let link = window.displayLink(target: driver, selector: #selector(DisplayLinkDriver.tick))

        driver.tick(link)

        #expect(capturedInterval != nil)
    }

    @Test("pause sets the display link's isPaused; resume clears it (#355)")
    func pauseAndResumeToggleIsPaused() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let driver = DisplayLinkDriver { _ in }
        driver.start(in: window)

        #expect(driver.displayLink?.isPaused == false)

        driver.pause()
        #expect(driver.displayLink?.isPaused == true)

        driver.resume()
        #expect(driver.displayLink?.isPaused == false)
    }

    @Test("pause and resume are safe no-ops before start(in:) has run (#355)")
    func pauseAndResumeWithoutActiveLink() {
        let driver = DisplayLinkDriver { _ in }

        driver.pause()
        driver.resume()

        #expect(driver.displayLink == nil)
    }

    @Test("start(in:) invalidates the previous link instead of leaking it (#355)")
    func startTwiceReplacesPreviousLinkWithoutLeaking() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let driver = DisplayLinkDriver { _ in }

        driver.start(in: window)
        // A new `CADisplayLink` instance is created on every call regardless
        // of the leak fix, so identity alone can't discriminate the bug — a
        // weak reference is: an un-invalidated link stays retained by the run
        // loop it was added to, so it would outlive this scope if `start(in:)`
        // failed to invalidate it before replacing `displayLink`.
        weak var firstLink = driver.displayLink
        #expect(firstLink != nil)

        driver.start(in: window)
        let secondLink = driver.displayLink

        #expect(secondLink != nil)
        #expect(firstLink == nil)
    }
}
