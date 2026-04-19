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
}
