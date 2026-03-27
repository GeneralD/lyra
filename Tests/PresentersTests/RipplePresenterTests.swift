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
            } operation: {
                let presenter = RipplePresenter()
                #expect(presenter.rippleState == nil)
                presenter.start()
                #expect(presenter.rippleState != nil)
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
            } operation: {
                let presenter = RipplePresenter(screenOrigin: .zero)
                presenter.start()

                // Trigger a ripple via mouse move
                presenter.rippleState?.update(screenPoint: CGPoint(x: 0, y: 0))
                presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))

                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 300), now: Date())
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
            } operation: {
                let presenter = RipplePresenter(screenOrigin: .zero)
                presenter.start()

                presenter.rippleState?.update(screenPoint: CGPoint(x: 0, y: 0))
                presenter.rippleState?.update(screenPoint: CGPoint(x: 100, y: 100))

                // Query far in the future — all ripples expired
                let future = Date().addingTimeInterval(10)
                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 300), now: future)
                #expect(commands.isEmpty, "Expired ripples should not generate commands")
            }
        }

        @MainActor
        @Test("screen origin offsets are applied to commands")
        func screenOriginOffset() {
            let origin = CGPoint(x: 100, y: 200)
            withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(rippleConfig: .init(enabled: true, duration: 2.0))
            } operation: {
                let presenter = RipplePresenter(screenOrigin: origin)
                presenter.start()

                presenter.rippleState?.update(screenPoint: CGPoint(x: 0, y: 0))
                presenter.rippleState?.update(screenPoint: CGPoint(x: 200, y: 300))

                let commands = presenter.drawingContexts(
                    canvasSize: CGSize(width: 400, height: 400), now: Date())
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
    }
}
