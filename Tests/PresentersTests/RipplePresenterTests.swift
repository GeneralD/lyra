import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Stub

private struct StubWallpaperInteractor: WallpaperInteractor {
    var rippleConfig: RippleStyle = .init()
    var playbackMode: WallpaperPlaybackMode { .cycle }
    var wallpaperSource: WallpaperStyle? { nil }

    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> { AsyncStream { $0.finish() } }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { Empty().eraseToAnyPublisher() }
}

/// Reference-type stub whose `rippleConfig` a test can mutate after injection so
/// the presenter (which reads it live) observes a config change — used to drive
/// the hot-reload `applyStyle()` seam (#41 PR3).
private final class MutableStubWallpaperInteractor: WallpaperInteractor, @unchecked Sendable {
    var rippleConfig: RippleStyle
    init(rippleConfig: RippleStyle) { self.rippleConfig = rippleConfig }
    var playbackMode: WallpaperPlaybackMode { .cycle }
    var wallpaperSource: WallpaperStyle? { nil }
    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> { AsyncStream { $0.finish() } }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { Empty().eraseToAnyPublisher() }
}

// Fixed date used for all tests to make RippleState deterministic.
private let fixedDate = Date(timeIntervalSinceReferenceDate: 0)

// MARK: - Tests

@Suite("RipplePresenter")
struct RipplePresenterTests {

    @Suite("isEnabled")
    struct IsEnabled {
        @MainActor
        @Test("reflects interactor config when enabled")
        func enabledReflectsConfig() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                #expect(presenter.isEnabled == true)
            }
        }

        @MainActor
        @Test("reflects interactor config when disabled")
        func disabledReflectsConfig() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: false))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                #expect(presenter.isEnabled == false)
            }
        }
    }

    @Suite("start")
    struct Start {
        @MainActor
        @Test("creates rippleState with interactor config")
        func createsRippleState() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, idle: 2.5))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                #expect(presenter.rippleState == nil)
                presenter.start()
                #expect(presenter.rippleState != nil)
            }
        }

        @MainActor
        @Test("creates rippleState but skips mouse monitor when disabled")
        func createsStateWhenDisabled() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: false))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                #expect(presenter.rippleState != nil)
                // stop should not crash even without mouse monitor
                presenter.stop()
            }
        }

        @MainActor
        @Test("stop then start rebuilds RippleState — the applied-config sentinel does not survive teardown")
        func restartAfterStopRebuildsState() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                let firstState = presenter.rippleState
                #expect(firstState != nil)

                presenter.stop()
                // The enabled config is unchanged across the restart: applyStyle
                // must treat it as a fresh apply (rebuilding state and re-attaching
                // the monitor), not diff it against the pre-stop sentinel.
                presenter.start()
                #expect(presenter.rippleState != nil)
                #expect(presenter.rippleState !== firstState)
                presenter.stop()
            }
        }
    }

    @Suite("idle")
    struct Idle {
        @MainActor
        @Test("delegates to rippleState")
        func idleDelegatesToState() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, idle: 0.05))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                presenter.rippleState?.update(screenPoint: .zero)

                // Idle ticks delegated to rippleState
                presenter.idle()
                presenter.idle()
                presenter.idle()
                presenter.idle()

                // After enough ticks, rippleState should have processed idle
                // (RippleState's internal behavior is tested separately)
            }
        }
    }

    @Suite("config access")
    struct ConfigAccess {
        @MainActor
        @Test("rippleConfig returns interactor config")
        func rippleConfigAccess() {
            let config = RippleStyle(enabled: true, duration: 2.0, idle: 5.0)
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: config)
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                #expect(presenter.rippleConfig.enabled == true)
                #expect(presenter.rippleConfig.idle == 5.0)
                #expect(presenter.rippleConfig.duration == 2.0)
            }
        }

        @MainActor
        @Test("isEnabled reflects ripple config")
        func isEnabledReflectsConfig() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: false))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                #expect(presenter.isEnabled == false)
            }
        }
    }

    @Suite("stop")
    struct Stop {
        @MainActor
        @Test("cleans up mouse monitor")
        func stopCleansUp() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                presenter.stop()
                // No crash = success (mouse monitor removed)
            }
        }
    }

    @Suite("drawingContexts")
    struct DrawCommands {
        @MainActor
        @Test("returns empty when rippleState is nil")
        func emptyWithoutState() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor()
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 300), now: Date())
                #expect(commands.isEmpty)
            }
        }

        @MainActor
        @Test("returns commands for active ripples")
        func commandsForActiveRipples() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 2.0))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()

                // Trigger a ripple via mouse move
                presenter.rippleState?.update(screenPoint: CGPoint(x: 0, y: 0))
                presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))

                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 300), now: fixedDate)
                #expect(!commands.isEmpty, "Should have draw commands for active ripples")
                #expect(commands.first!.rect.width >= 0)
                #expect(commands.first!.color.alpha > 0)
            }
        }

        @MainActor
        @Test("expired ripples are excluded")
        func expiredExcluded() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 0.1))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()

                presenter.rippleState?.update(screenPoint: CGPoint(x: 0, y: 0))
                presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))

                // Query far in the future — all ripples expired
                let future = fixedDate.addingTimeInterval(10)
                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 300), now: future)
                #expect(commands.isEmpty, "Expired ripples should not generate commands")
            }
        }

        @MainActor
        @Test("gradient color uses first color for HSB base")
        func gradientColorBase() {
            let config = RippleStyle(enabled: true, color: .gradient(["#FF0000", "#00FF00"]), duration: 2.0)
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: config)
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()

                presenter.rippleState?.update(screenPoint: CGPoint(x: 0, y: 0))
                presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))

                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 300), now: fixedDate)
                #expect(!commands.isEmpty)
                #expect(commands.first!.color.alpha > 0)
            }
        }

        @MainActor
        @Test("screen origin offsets are applied to commands")
        func screenOriginOffset() {
            let screenRect = CGRect(x: 100, y: 200, width: 1920, height: 1080)
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 2.0))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter(screenRect: screenRect)
                presenter.start()

                presenter.rippleState?.update(screenPoint: CGPoint(x: 0, y: 0))
                presenter.rippleState?.update(screenPoint: CGPoint(x: 200, y: 300))

                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 400), now: fixedDate)
                guard let cmd = commands.first else {
                    #expect(Bool(false), "Should have at least one command")
                    return
                }
                // center: x = 200 - 100 = 100, y = 400 - (300 - 200) = 300
                let centerX = cmd.rect.midX
                let centerY = cmd.rect.midY
                #expect(abs(centerX - 100) < 1)
                #expect(abs(centerY - 300) < 1)
            }
        }

        @MainActor
        @Test("circle shape is propagated to drawing context")
        func circleShapePropagated() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(
                    rippleConfig: .init(enabled: true, duration: 2.0, shape: .circle))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))
                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 300), now: fixedDate)
                #expect(commands.first?.shape == .circle)
            }
        }

        @MainActor
        @Test("polygon shape is propagated to drawing context")
        func polygonShapePropagated() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(
                    rippleConfig: .init(
                        enabled: true, duration: 2.0,
                        shape: .polygon(sides: 6, angle: 15)))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))
                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 300), now: fixedDate)
                #expect(commands.first?.shape == .polygon(sides: 6, angle: 15))
            }
        }
    }

    @Suite("processMouseMove")
    struct ProcessMouseMove {
        private static let screenRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        @MainActor
        @Test("rejects point outside screenRect and clears mouseInScreen (#271)")
        func rejectsOutsidePoint() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 2.0))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter(screenRect: Self.screenRect)
                presenter.start()
                // An in-screen sample sets mouseInScreen = true and spawns a ripple.
                presenter.processMouseMove(at: CGPoint(x: 960, y: 540), time: 1.0)
                let spawned = presenter.rippleState?.ripples.count ?? 0
                #expect(spawned > 0)
                // An off-screen sample clears the hover flag without further work,
                // so a following idle tick spawns no idle ripple.
                presenter.processMouseMove(at: CGPoint(x: 5000, y: 5000), time: 2.0)
                let before = presenter.rippleState?.ripples.count ?? 0
                presenter.idle()
                #expect((presenter.rippleState?.ripples.count ?? 0) == before)
            }
        }

        @MainActor
        @Test("accepts point inside screenRect and spawns ripple (#271)")
        func acceptsInsidePoint() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 2.0))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter(screenRect: Self.screenRect)
                presenter.start()
                presenter.processMouseMove(at: CGPoint(x: 960, y: 540), time: 1.0)
                #expect((presenter.rippleState?.ripples.count ?? 0) > 0)
            }
        }

        @MainActor
        @Test("throttles samples arriving within 33 ms (#271)")
        func throttlesRapidSamples() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 2.0))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter(screenRect: Self.screenRect)
                presenter.start()
                presenter.processMouseMove(at: CGPoint(x: 100, y: 100), time: 1.0)
                let afterFirst = presenter.rippleState?.ripples.count ?? 0
                // Second sample only 10 ms later is dropped by the throttle.
                presenter.processMouseMove(at: CGPoint(x: 800, y: 800), time: 1.010)
                #expect((presenter.rippleState?.ripples.count ?? 0) == afterFirst)
                // A sample past the 33 ms window is processed again.
                presenter.processMouseMove(at: CGPoint(x: 800, y: 800), time: 1.050)
                #expect((presenter.rippleState?.ripples.count ?? 0) > afterFirst)
            }
        }
    }

    @Suite("handleGlobalMouseMove")
    struct HandleGlobalMouseMove {
        @MainActor
        @Test("hops onto the main actor and applies screen exclusion (#271)")
        func bridgesMonitorCallback() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 2.0))
                $0.date = .init { fixedDate }
            } operation: {
                // A zero screenRect can never contain the live cursor, so the
                // bridged call must run synchronously on the main actor and exit
                // via the exclusion guard without spawning a ripple.
                let presenter = RipplePresenter(screenRect: .zero)
                presenter.start()
                presenter.handleGlobalMouseMove()
                #expect(presenter.rippleState?.ripples.isEmpty == true)
                #expect(!presenter.isAnimating)
            }
        }
    }

    @Suite("hot reload toggle (#41 PR3)")
    struct HotReloadToggle {
        @MainActor
        @Test("a config ping that enables ripple rebuilds RippleState")
        func enableViaConfigPingRebuildsState() async {
            let interactor = MutableStubWallpaperInteractor(rippleConfig: .init(enabled: false))
            let config = FakeConfigInteractor()
            // start() inside the scope so the RippleState it builds captures the
            // injected date (RippleState reads `@Dependency(\.date)` internally).
            let presenter = withDependencies {
                $0.wallpaperInteractor = interactor
                $0.configInteractor = config
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                return presenter
            }

            let disabledState = presenter.rippleState
            #expect(disabledState != nil)
            #expect(!presenter.isEnabled)

            // Enable the ripple through config: the ping rebuilds RippleState to a
            // fresh (enabled) instance and arms the mouse monitor.
            interactor.rippleConfig = .init(enabled: true)
            config.fire()
            await flushMainQueue()

            #expect(presenter.rippleState !== disabledState)
            #expect(presenter.isEnabled)
            presenter.stop()
        }

        @MainActor
        @Test("a config ping that changes only a live-read field keeps RippleState")
        func unrelatedConfigPingKeepsState() async {
            let interactor = MutableStubWallpaperInteractor(
                rippleConfig: .init(enabled: true, duration: 2.0))
            let config = FakeConfigInteractor()
            let presenter = withDependencies {
                $0.wallpaperInteractor = interactor
                $0.configInteractor = config
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                return presenter
            }

            let state = presenter.rippleState
            #expect(state != nil)

            // Change only the color — a field read live in drawingContexts, never
            // frozen into RippleState. applyStyle must not rebuild, so the same
            // RippleState instance (and any live ripples it holds) survives the edit.
            interactor.rippleConfig = .init(enabled: true, color: .solid("#123456"), duration: 2.0)
            config.fire()
            await flushMainQueue()

            #expect(presenter.rippleState === state)
            presenter.stop()
        }

        @MainActor
        @Test("a rebuild ping clears the hover flag so idle ripples don't spawn at the origin (#41 PR3 review, F3)")
        func rebuildPingClearsHoverState() async {
            let clock = MutableClock(now: fixedDate)
            let interactor = MutableStubWallpaperInteractor(
                rippleConfig: .init(enabled: true, duration: 2.0, idle: 1.0))
            let config = FakeConfigInteractor()
            let presenter = withDependencies {
                $0.wallpaperInteractor = interactor
                $0.configInteractor = config
                $0.date = .init { clock.now }
            } operation: {
                let presenter = RipplePresenter()
                presenter.updateScreenRect(CGRect(x: 0, y: 0, width: 200, height: 200))
                presenter.start()
                return presenter
            }

            // Cursor moves inside the overlay: hover is active on the old state.
            presenter.handleMouseLocation(CGPoint(x: 100, y: 100))

            // A rebuild-triggering edit (duration change) replaces RippleState with
            // a fresh instance whose cursor position starts at .zero. The hover flag
            // must be cleared too, or idle() would spawn idle ripples at the screen
            // origin until a real mouse move re-establishes the position.
            interactor.rippleConfig = .init(enabled: true, duration: 3.0, idle: 1.0)
            config.fire()
            await flushMainQueue()

            // Advance well past the idle interval and tick idle: with the hover flag
            // cleared, nothing spawns. Without the F3 fix, an idle ripple would
            // appear at the origin here.
            presenter.idle()
            clock.now = fixedDate.addingTimeInterval(5)
            presenter.idle()

            #expect(presenter.rippleState?.ripples.isEmpty == true)
            presenter.stop()
        }
    }

    @Suite("isAnimating")
    struct IsAnimating {
        @MainActor
        @Test("stays false while no ripple has been spawned")
        func falseWhenNoRipples() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                presenter.idle()
                #expect(!presenter.isAnimating)
            }
        }

        @MainActor
        @Test("becomes true while a freshly spawned ripple is alive")
        func trueWhileRippleAlive() {
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 2.0))
                $0.date = .init { fixedDate }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                presenter.rippleState?.update(screenPoint: CGPoint(x: 0, y: 0))
                presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))
                presenter.idle()
                #expect(presenter.isAnimating)
            }
        }

        @MainActor
        @Test("returns to false once every ripple has expired")
        func falseAfterExpiry() {
            let clock = MutableClock(now: fixedDate)
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 0.1))
                $0.date = .init { clock.now }
            } operation: {
                let presenter = RipplePresenter()
                presenter.start()
                presenter.rippleState?.update(screenPoint: CGPoint(x: 0, y: 0))
                presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))
                presenter.idle()
                #expect(presenter.isAnimating)

                // Advance well past the ripple's visible window; the next idle
                // tick observes no live ripples and closes the animation gate.
                // The pointer never re-entered the screen, so no new ripple is
                // spawned — the prune must still drain the array so the *next*
                // tick short-circuits without reading the clock (#258).
                clock.now = fixedDate.addingTimeInterval(10)
                presenter.idle()
                #expect(!presenter.isAnimating)
                #expect(presenter.rippleState?.ripples.isEmpty == true)
            }
        }
    }
}

/// Mutable date source for advancing `\.date` within one `@MainActor` test.
/// The unchecked Sendable conformance is safe because tests mutate it only on
/// that actor.
private final class MutableClock: @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
}
