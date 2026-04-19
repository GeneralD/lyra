import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Stub

private struct StubWallpaperInteractor: WallpaperInteractor {
    var rippleConfig: RippleStyle = .init()

    func resolveWallpaper() async throws -> WallpaperState { .init() }
}

// MARK: - Screen Rects

private let mainScreenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
private let secondaryScreenRect = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
private let leftScreenRect = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
private let enabledConfig = RippleStyle(enabled: true, duration: 2.0)

// MARK: - Tests

@Suite("RipplePresenter — Screen Bounds")
struct RippleScreenBoundsTests {

    // MARK: - Mouse Filtering

    @Suite("mouse filtering")
    struct MouseFiltering {
        @MainActor
        @Test("mouse within screen rect adds ripple")
        func insideAddsRipple() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                presenter.handleMouseLocation(CGPoint(x: 2000, y: 500))
                presenter.handleMouseLocation(CGPoint(x: 2100, y: 600))

                #expect(!presenter.rippleState!.ripples.isEmpty)
            }
        }

        @MainActor
        @Test("mouse outside screen rect is ignored")
        func outsideIgnored() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                // Main screen coordinates — outside secondary screen
                presenter.handleMouseLocation(CGPoint(x: 500, y: 400))
                presenter.handleMouseLocation(CGPoint(x: 600, y: 500))

                #expect(presenter.rippleState!.ripples.isEmpty)
            }
        }

        @MainActor
        @Test("mouse on screen rect edge counts as inside")
        func edgeCountsAsInside() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                // Exact edge of secondary screen, then move far enough to trigger
                presenter.handleMouseLocation(CGPoint(x: 1920, y: 0))
                presenter.handleMouseLocation(CGPoint(x: 1920 + 100, y: 100))

                #expect(!presenter.rippleState!.ripples.isEmpty)
            }
        }

        @MainActor
        @Test("multiple movements within screen rect all register")
        func multipleMovementsRegister() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                // Points spread > 40px apart (threshold in RippleState)
                presenter.handleMouseLocation(CGPoint(x: 2000, y: 100))
                presenter.handleMouseLocation(CGPoint(x: 2100, y: 200))
                presenter.handleMouseLocation(CGPoint(x: 2200, y: 300))
                presenter.handleMouseLocation(CGPoint(x: 2300, y: 400))

                #expect(presenter.rippleState!.ripples.count >= 3)
            }
        }
    }

    // MARK: - Boundary Conditions

    @Suite("boundary conditions")
    struct BoundaryConditions {
        @MainActor
        @Test("main screen rect at origin preserves existing behavior")
        func mainScreenPreservesExisting() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: mainScreenRect)
                presenter.start()

                presenter.handleMouseLocation(CGPoint(x: 100, y: 100))
                presenter.handleMouseLocation(CGPoint(x: 200, y: 200))

                #expect(!presenter.rippleState!.ripples.isEmpty)
            }
        }

        @MainActor
        @Test("negative origin screen accepts points within bounds")
        func negativeOriginAccepts() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: leftScreenRect)
                presenter.start()

                presenter.handleMouseLocation(CGPoint(x: -1000, y: 500))
                presenter.handleMouseLocation(CGPoint(x: -900, y: 600))

                #expect(!presenter.rippleState!.ripples.isEmpty)
            }
        }

        @MainActor
        @Test("negative origin screen rejects main screen points")
        func negativeOriginRejectsMainPoints() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: leftScreenRect)
                presenter.start()

                presenter.handleMouseLocation(CGPoint(x: 500, y: 500))
                presenter.handleMouseLocation(CGPoint(x: 600, y: 600))

                #expect(presenter.rippleState!.ripples.isEmpty)
            }
        }

        @MainActor
        @Test("zero-size screen rect rejects all points")
        func zeroSizeRejectsAll() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: .zero)
                presenter.start()

                presenter.handleMouseLocation(CGPoint(x: 0, y: 0))
                presenter.handleMouseLocation(CGPoint(x: 100, y: 100))

                #expect(presenter.rippleState!.ripples.isEmpty)
            }
        }
    }

    // MARK: - Idle with Screen Bounds

    @Suite("idle with screen bounds")
    struct IdleWithScreenBounds {
        @MainActor
        @Test("idle fires when mouse last moved within screen")
        func idleFiresWhenInside() async throws {
            let config = RippleStyle(enabled: true, duration: 2.0, idle: 0.01)
            try await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: config)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                // Move mouse inside screen
                presenter.handleMouseLocation(CGPoint(x: 2000, y: 500))

                let deadline = ContinuousClock.now + .seconds(2)
                var idleRippleFound = false
                while !idleRippleFound, ContinuousClock.now < deadline {
                    presenter.idle()
                    idleRippleFound = presenter.rippleState?.ripples.contains(where: \.idle) ?? false
                    try await Task.sleep(for: .milliseconds(20))
                }

                #expect(idleRippleFound, "Idle ripple should fire when mouse is inside screen")
            }
        }

        @MainActor
        @Test("idle suppressed when mouse never entered screen")
        func idleSuppressedWhenOutside() async throws {
            let config = RippleStyle(enabled: true, duration: 2.0, idle: 0.01)
            try await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: config)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                // Mouse only outside screen
                presenter.handleMouseLocation(CGPoint(x: 500, y: 500))

                try await Task.sleep(for: .milliseconds(50))
                for _ in 0..<10 {
                    presenter.idle()
                }

                let idleRipples = presenter.rippleState?.ripples.filter(\.idle) ?? []
                #expect(idleRipples.isEmpty, "Idle ripples should not fire when mouse is outside screen")
            }
        }

        @MainActor
        @Test("mouse leaving screen suppresses subsequent idle ripples")
        func leavingSuppressesIdle() async throws {
            let config = RippleStyle(enabled: true, duration: 2.0, idle: 0.01)
            try await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: config)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                // Enter, then leave screen
                presenter.handleMouseLocation(CGPoint(x: 2000, y: 500))
                presenter.handleMouseLocation(CGPoint(x: 500, y: 500))  // outside

                let countBefore = presenter.rippleState?.ripples.filter(\.idle).count ?? 0

                try await Task.sleep(for: .milliseconds(50))
                for _ in 0..<10 {
                    presenter.idle()
                }

                let countAfter = presenter.rippleState?.ripples.filter(\.idle).count ?? 0
                #expect(countAfter == countBefore, "Idle should not fire after mouse left screen")
            }
        }

        @MainActor
        @Test("mouse re-entering screen resumes idle ripples")
        func reEntryResumesIdle() async throws {
            let config = RippleStyle(enabled: true, duration: 2.0, idle: 0.01)
            try await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: config)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                // Enter → leave → re-enter
                presenter.handleMouseLocation(CGPoint(x: 2000, y: 500))
                presenter.handleMouseLocation(CGPoint(x: 500, y: 500))  // leave
                presenter.handleMouseLocation(CGPoint(x: 2200, y: 600))  // re-enter
                presenter.handleMouseLocation(CGPoint(x: 2300, y: 700))

                let deadline = ContinuousClock.now + .seconds(2)
                var idleRippleFound = false
                while !idleRippleFound, ContinuousClock.now < deadline {
                    presenter.idle()
                    idleRippleFound = presenter.rippleState?.ripples.contains(where: \.idle) ?? false
                    try await Task.sleep(for: .milliseconds(20))
                }

                #expect(idleRippleFound, "Idle should resume after mouse re-enters screen")
            }
        }
    }

    // MARK: - Dynamic Screen Rect Update

    @Suite("dynamic screen rect update")
    struct DynamicUpdate {
        @MainActor
        @Test("updateScreenRect changes filtering boundary")
        func updateChangesFilterBoundary() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: mainScreenRect)
                presenter.start()

                // Secondary screen points rejected with main screen rect
                presenter.handleMouseLocation(CGPoint(x: 2000, y: 500))
                presenter.handleMouseLocation(CGPoint(x: 2100, y: 600))
                #expect(presenter.rippleState!.ripples.isEmpty)

                // Update to secondary screen
                presenter.updateScreenRect(secondaryScreenRect)

                // Same region now accepted
                presenter.handleMouseLocation(CGPoint(x: 2200, y: 500))
                presenter.handleMouseLocation(CGPoint(x: 2300, y: 600))
                #expect(!presenter.rippleState!.ripples.isEmpty)
            }
        }

        @MainActor
        @Test("updateScreenRect updates drawingContexts origin")
        func updateChangesDrawingOrigin() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                presenter.handleMouseLocation(CGPoint(x: 2000, y: 100))
                presenter.handleMouseLocation(CGPoint(x: 2100, y: 500))

                let canvasSize = CGSize(width: 1920, height: 1080)
                let commands = presenter.drawingContexts(canvasSize: canvasSize, now: Date())
                guard let cmd = commands.last else {
                    Issue.record("Should have at least one command")
                    return
                }

                // x = 2100 - 1920 = 180, y = 1080 - (500 - 0) = 580
                #expect(abs(cmd.rect.midX - 180) < 1)
                #expect(abs(cmd.rect.midY - 580) < 1)
            }
        }

        @MainActor
        @Test("old screen rect no longer applies after update")
        func oldRectNoLongerApplies() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: mainScreenRect)
                presenter.start()

                presenter.updateScreenRect(secondaryScreenRect)

                // Main screen points now rejected
                presenter.handleMouseLocation(CGPoint(x: 500, y: 400))
                presenter.handleMouseLocation(CGPoint(x: 600, y: 500))
                #expect(presenter.rippleState!.ripples.isEmpty)
            }
        }
    }

    // MARK: - Coordinate Transformation Invariants

    @Suite("coordinate transformation invariants")
    struct CoordinateInvariants {
        @MainActor
        @Test("x equals position.x minus screenRect.origin.x")
        func xCoordinateInvariant() {
            let screenRect = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
            let point = CGPoint(x: 2500, y: 500)

            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(
                    rippleConfig: .init(enabled: true, duration: 2.0))
            } operation: {
                let presenter = RipplePresenter(screenRect: screenRect)
                presenter.start()

                presenter.handleMouseLocation(CGPoint(x: 2000, y: 100))
                presenter.handleMouseLocation(point)

                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 1920, height: 1080), now: Date())
                guard let cmd = commands.last else {
                    Issue.record("Should have command")
                    return
                }

                let expectedX = point.x - screenRect.origin.x  // 2500 - 1920 = 580
                #expect(abs(cmd.rect.midX - expectedX) < 1)
            }
        }

        @MainActor
        @Test("y equals canvasHeight minus (position.y minus screenRect.origin.y)")
        func yCoordinateInvariant() {
            let screenRect = CGRect(x: 1920, y: 25, width: 1920, height: 1055)
            let point = CGPoint(x: 2500, y: 500)
            let canvasHeight: CGFloat = 1055

            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(
                    rippleConfig: .init(enabled: true, duration: 2.0))
            } operation: {
                let presenter = RipplePresenter(screenRect: screenRect)
                presenter.start()

                presenter.handleMouseLocation(CGPoint(x: 2000, y: 100))
                presenter.handleMouseLocation(point)

                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 1920, height: canvasHeight), now: Date())
                guard let cmd = commands.last else {
                    Issue.record("Should have command")
                    return
                }

                // 1055 - (500 - 25) = 580
                let expectedY = canvasHeight - (point.y - screenRect.origin.y)
                #expect(abs(cmd.rect.midY - expectedY) < 1)
            }
        }

        @MainActor
        @Test("ripple count never increases when all events are outside screen")
        func noIncreaseWhenOutside() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: enabledConfig)
            } operation: {
                let presenter = RipplePresenter(screenRect: secondaryScreenRect)
                presenter.start()

                let initialCount = presenter.rippleState!.ripples.count

                // Many movements, all on main screen (outside secondary)
                for i in stride(from: 0, to: 1000, by: 50) {
                    presenter.handleMouseLocation(CGPoint(x: i, y: i))
                }

                #expect(presenter.rippleState!.ripples.count == initialCount)
            }
        }
    }
}
