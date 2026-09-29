import AppKit
import Domain
import Testing

@testable import AppKitScreenProvider

@Suite("AppKitScreenProvider")
struct AppKitScreenProviderTests {
    @MainActor
    @Test("screens mirrors NSScreen.screens")
    func screens() {
        let provider = AppKitScreenProvider()

        #expect(provider.screens.count == NSScreen.screens.count)
        #expect(provider.screens.map(\.frame) == NSScreen.screens.map(\.frame))
    }

    @MainActor
    @Test("mainScreen mirrors NSScreen.main")
    func mainScreen() {
        let provider = AppKitScreenProvider()

        #expect(provider.mainScreen?.frame == NSScreen.main?.frame)
        #expect(provider.mainScreen?.visibleFrame == NSScreen.main?.visibleFrame)
    }

    @MainActor
    @Test("windowOccupancy returns a non-negative value for a real screen")
    func windowOccupancyForRealScreen() {
        let provider = AppKitScreenProvider()
        guard let screen = provider.mainScreen else { return }

        // Exercises the full delegation path: CGWindowList enumeration,
        // filtering, CG→AppKit conversion, and area-sum occupancy math.
        // Value may exceed 1 due to overlapping windows double-counting —
        // we only assert it's finite and non-negative.
        let occupancy = provider.windowOccupancy(for: screen)
        #expect(occupancy >= 0)
        #expect(occupancy.isFinite)
    }

    @MainActor
    @Test("windowOccupancy of a zero-area synthetic screen is 1")
    func windowOccupancyZeroScreen() {
        let provider = AppKitScreenProvider()
        let zero = ScreenInfo(frame: .zero, visibleFrame: .zero)

        // Delegates to ScreenInfo.occupancy which short-circuits to 1 on zero area.
        #expect(provider.windowOccupancy(for: zero) == 1)
    }

    @MainActor
    @Test("windowCoverage returns a non-negative, bounded value for a real screen")
    func windowCoverageForRealScreen() {
        let provider = AppKitScreenProvider()
        guard let screen = provider.mainScreen else { return }

        // Exercises the full delegation path: CGWindowList enumeration,
        // filtering, CG→AppKit conversion, and union-area coverage math.
        let coverage = provider.windowCoverage(for: screen)
        #expect(coverage >= 0)
        #expect(coverage <= 1)
    }

    @MainActor
    @Test("windowCoverage of a zero-area synthetic screen is 1")
    func windowCoverageZeroScreen() {
        let provider = AppKitScreenProvider()
        let zero = ScreenInfo(frame: .zero, visibleFrame: .zero)

        // Delegates to ScreenInfo.coverage which short-circuits to 1 on zero area.
        #expect(provider.windowCoverage(for: zero) == 1)
    }

    @Suite("flippedToAppKit")
    struct FlippedToAppKit {
        @Test("flips y relative to primary height")
        func flipsYRelativeToPrimary() {
            let primaryHeight: CGFloat = 1080
            let cgRect = CGRect(x: 100, y: 0, width: 200, height: 300)

            let appKitRect = cgRect.flippedToAppKit(primaryHeight: primaryHeight)

            #expect(appKitRect.origin.x == 100)
            #expect(appKitRect.origin.y == 780)  // 1080 - 0 - 300
            #expect(appKitRect.width == 200)
            #expect(appKitRect.height == 300)
        }

        @Test("rect at CG origin lands on the top-left of primary in AppKit")
        func cgOriginLandsAtTopLeft() {
            let primaryHeight: CGFloat = 1000
            let cgRect = CGRect(x: 0, y: 0, width: 50, height: 50)

            let r = cgRect.flippedToAppKit(primaryHeight: primaryHeight)

            #expect(r.origin == CGPoint(x: 0, y: 950))
        }

        @Test("rect on a secondary display below primary keeps negative y in AppKit")
        func secondaryBelowPrimary() {
            let primaryHeight: CGFloat = 1080
            // Window on a display stacked below primary: CG y > primaryHeight
            let cgRect = CGRect(x: 0, y: 1080, width: 1920, height: 1080)

            let r = cgRect.flippedToAppKit(primaryHeight: primaryHeight)

            // AppKit y = 1080 - 1080 - 1080 = -1080 (below primary in AppKit)
            #expect(r.origin.y == -1080)
            #expect(r.height == 1080)
        }

        @Test("rect size is preserved")
        func sizePreserved() {
            let r = CGRect(x: 42, y: 123, width: 321, height: 234)
                .flippedToAppKit(primaryHeight: 2000)

            #expect(r.size == CGSize(width: 321, height: 234))
        }
    }

    @Suite("occupancy")
    struct Occupancy {
        private let mainScreen = ScreenInfo(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))
        private let secondaryScreen = ScreenInfo(
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1055))

        @Test("returns 0 when no windows overlap the screen")
        func noOverlap() {
            let occupancy = secondaryScreen.occupancy(
                windows: [CGRect(x: 0, y: 0, width: 500, height: 500)])

            #expect(occupancy == 0)
        }

        @Test("returns 1 when a window fully covers the screen")
        func fullyCovered() {
            let occupancy = mainScreen.occupancy(
                windows: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])

            #expect(occupancy == 1)
        }

        @Test("returns fraction for partial overlap")
        func partialOverlap() {
            // 960 x 1080 = half of 1920 x 1080
            let occupancy = mainScreen.occupancy(
                windows: [CGRect(x: 0, y: 0, width: 960, height: 1080)])

            #expect(abs(occupancy - 0.5) < 0.0001)
        }

        @Test("sums multiple overlapping windows (no union — overlaps double-count)")
        func sumsMultipleWindows() {
            // Two identical half-screen windows — each contributes 0.5, sum is 1.0.
            // The implementation approximates coverage by area sum, not by geometric union.
            let occupancy = mainScreen.occupancy(
                windows: [
                    CGRect(x: 0, y: 0, width: 960, height: 1080),
                    CGRect(x: 0, y: 0, width: 960, height: 1080),
                ])

            #expect(abs(occupancy - 1.0) < 0.0001)
        }

        @Test("only counts the intersecting portion")
        func clipsToScreen() {
            // Window spans both displays, but only half lands on secondary
            let occupancy = secondaryScreen.occupancy(
                windows: [CGRect(x: 960, y: 0, width: 1920, height: 1080)])

            // Intersection with secondary (x: 1920..3840) is x: 1920..2880 → 960 x 1080
            #expect(abs(occupancy - 0.5) < 0.0001)
        }

        @Test("returns 1 for a zero-area screen")
        func zeroScreenArea() {
            let zeroScreen = ScreenInfo(frame: .zero, visibleFrame: .zero)

            let occupancy = zeroScreen.occupancy(
                windows: [CGRect(x: 0, y: 0, width: 100, height: 100)])

            #expect(occupancy == 1)
        }

        @Test("returns 0 for an empty window list")
        func noWindows() {
            let occupancy = mainScreen.occupancy(windows: [])

            #expect(occupancy == 0)
        }
    }

    @Suite("Coverage")
    struct Coverage {
        private let screen = ScreenInfo(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000))

        @Test("returns 1.0 when a single window fully covers the visible frame")
        func fullyCoveredBySingleWindow() {
            let coverage = screen.coverage(
                windows: [CGRect(x: 0, y: 0, width: 1000, height: 1000)])

            #expect(coverage == 1.0)
        }

        @Test(
            "returns 0.5 for two identical half-screen windows (contrast: occupancy sums to 1.0)"
        )
        func identicalHalfScreenWindowsUnionNotSummed() {
            let halfScreen = CGRect(x: 0, y: 0, width: 1000, height: 500)

            let coverage = screen.coverage(windows: [halfScreen, halfScreen])
            let occupancy = screen.occupancy(windows: [halfScreen, halfScreen])

            #expect(abs(coverage - 0.5) < 0.0001)
            #expect(abs(occupancy - 1.0) < 0.0001)
        }

        @Test("unions two overlapping windows (each 0.5, overlap 0.25) into 0.75")
        func overlappingWindowsUnion() {
            // Top half: y 0..500 (area 500,000 = 0.5 of the 1,000,000 screen).
            let topHalf = CGRect(x: 0, y: 0, width: 1000, height: 500)
            // Middle band: y 250..750 (area 500,000 = 0.5), overlapping topHalf
            // over y 250..500 (area 250,000 = 0.25).
            let middleBand = CGRect(x: 0, y: 250, width: 1000, height: 500)

            let coverage = screen.coverage(windows: [topHalf, middleBand])

            #expect(abs(coverage - 0.75) < 0.0001)
        }

        @Test("returns 0 for a window entirely outside the visible frame")
        func windowOutsideVisibleFrame() {
            let outside = CGRect(x: 2000, y: 2000, width: 500, height: 500)

            let coverage = screen.coverage(windows: [outside])

            #expect(coverage == 0)
        }

        @Test("returns 0 for a window covering only a menu-bar-like strip inside frame but outside visibleFrame")
        func windowCoveringOnlyOutsideVisibleStrip() {
            let screenWithMenuBar = ScreenInfo(
                frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 975))
            // Inside `frame` (y 0..1000) but entirely outside `visibleFrame` (y 0..975).
            let menuBarStrip = CGRect(x: 0, y: 975, width: 1000, height: 25)

            let coverage = screenWithMenuBar.coverage(windows: [menuBarStrip])

            #expect(coverage == 0)
        }

        @Test("returns 0 for an empty window list")
        func noWindows() {
            let coverage = screen.coverage(windows: [])

            #expect(coverage == 0)
        }

        @Test("returns 1 for a zero-area visible frame")
        func zeroVisibleFrameArea() {
            let zeroScreen = ScreenInfo(frame: .zero, visibleFrame: .zero)

            let coverage = zeroScreen.coverage(
                windows: [CGRect(x: 0, y: 0, width: 100, height: 100)])

            #expect(coverage == 1)
        }

        @Test("never exceeds 1.0 even with multiple overlapping full-coverage windows")
        func neverExceedsOne() {
            let full = CGRect(x: 0, y: 0, width: 1000, height: 1000)

            let coverage = screen.coverage(windows: [full, full, full])

            #expect(coverage == 1.0)
        }

        @Test("clips a window that partially overflows the visible frame before measuring it")
        func clipsPartiallyOverflowingWindow() {
            // Overflows 500pt to the left of the screen (x -500..500); only the
            // x 0..500 portion (area 500,000 = 0.5 of the screen) should count.
            let overflowing = CGRect(x: -500, y: 0, width: 1000, height: 1000)

            let coverage = screen.coverage(windows: [overflowing])

            #expect(abs(coverage - 0.5) < 0.0001)
        }
    }
}
