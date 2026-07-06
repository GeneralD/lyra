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
}
