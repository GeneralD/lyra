import AppKit
import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import WallpaperInteractor

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var style: AppStyle = .init()
    var appStyle: AppStyle { style }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

/// Stub UseCase that resolves each location to a predictable URL with a configurable delay.
/// Delays let tests exercise out-of-order completion in cycle mode.
private struct StubWallpaperUseCase: WallpaperUseCase, Sendable {
    var results: [String: URL] = [:]
    var delaysMillis: [String: UInt64] = [:]
    var failures: Set<String> = []

    func resolveWallpaper(value: String?, configDir: String) async throws -> URL? {
        guard let value else { return nil }
        if let ms = delaysMillis[value], ms > 0 {
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
        }
        if failures.contains(value) {
            throw StubError.failed
        }
        return results[value]
    }
}

private enum StubError: Error { case failed }

private func collect(_ stream: AsyncStream<ResolvedWallpaperItem>) async -> [ResolvedWallpaperItem] {
    await stream.reduce(into: [ResolvedWallpaperItem]()) { $0.append($1) }
}

@Suite("WallpaperInteractor")
struct WallpaperInteractorImplTests {

    @Test("resolvedWallpapers emits empty stream when no wallpaper configured")
    func noWallpaperConfig() async throws {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
            $0.wallpaperUseCase = StubWallpaperUseCase()
        } operation: {
            WallpaperInteractorImpl()
        }

        let items = await collect(interactor.resolvedWallpapers())
        #expect(items.isEmpty)
        #expect(interactor.playbackMode == .cycle)
    }

    @Test("resolvedWallpapers emits single item for legacy single-location config")
    func singleItem() async throws {
        let resolved = URL(fileURLWithPath: "/resolved/bg.mp4")
        let wallpaper = WallpaperStyle(location: "bg.mp4", start: 10, end: 180, scale: 1.25)
        let style = AppStyle(wallpaper: wallpaper, configDir: "/config")

        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
            $0.wallpaperUseCase = StubWallpaperUseCase(results: ["bg.mp4": resolved])
        } operation: {
            WallpaperInteractorImpl()
        }

        let items = await collect(interactor.resolvedWallpapers())
        #expect(items == [ResolvedWallpaperItem(url: resolved, start: 10, end: 180, scale: 1.25)])
    }

    @Test("cycle mode emits items in configured order even when later entries resolve first")
    func cycleOrderWithMixedLatency() async throws {
        let style = AppStyle(
            wallpaper: WallpaperStyle(
                items: [
                    WallpaperItem(location: "slow.mp4", scale: 1.1),
                    WallpaperItem(location: "fast.mp4", scale: 1.4),
                ],
                mode: .cycle
            ),
            configDir: "/config"
        )
        let slow = URL(fileURLWithPath: "/resolved/slow.mp4")
        let fast = URL(fileURLWithPath: "/resolved/fast.mp4")
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
            $0.wallpaperUseCase = StubWallpaperUseCase(
                results: ["slow.mp4": slow, "fast.mp4": fast],
                delaysMillis: ["slow.mp4": 50, "fast.mp4": 0]
            )
        } operation: {
            WallpaperInteractorImpl()
        }

        let items = await collect(interactor.resolvedWallpapers())
        #expect(items.map(\.url) == [slow, fast])
        #expect(items.map(\.scale) == [1.1, 1.4])
        #expect(interactor.playbackMode == .cycle)
    }

    @Test("cycle mode skips failed items but preserves remaining order")
    func cycleSkipsFailures() async throws {
        let style = AppStyle(
            wallpaper: WallpaperStyle(
                items: [
                    WallpaperItem(location: "broken.mp4"),
                    WallpaperItem(location: "ok.mp4"),
                ],
                mode: .cycle
            ),
            configDir: "/config"
        )
        let ok = URL(fileURLWithPath: "/resolved/ok.mp4")
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
            $0.wallpaperUseCase = StubWallpaperUseCase(
                results: ["ok.mp4": ok],
                failures: ["broken.mp4"]
            )
        } operation: {
            WallpaperInteractorImpl()
        }

        let items = await collect(interactor.resolvedWallpapers())
        #expect(items.map(\.url) == [ok])
    }

    @Test("shuffle mode emits items as they complete (first-resolve first)")
    func shuffleEmitsAsCompleted() async throws {
        let style = AppStyle(
            wallpaper: WallpaperStyle(
                items: [
                    WallpaperItem(location: "slow.mp4", scale: 1.2),
                    WallpaperItem(location: "fast.mp4", scale: 1.5),
                ],
                mode: .shuffle
            ),
            configDir: "/config"
        )
        let slow = URL(fileURLWithPath: "/resolved/slow.mp4")
        let fast = URL(fileURLWithPath: "/resolved/fast.mp4")
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
            $0.wallpaperUseCase = StubWallpaperUseCase(
                results: ["slow.mp4": slow, "fast.mp4": fast],
                delaysMillis: ["slow.mp4": 80, "fast.mp4": 0]
            )
        } operation: {
            WallpaperInteractorImpl()
        }

        let items = await collect(interactor.resolvedWallpapers())
        #expect(items.first?.url == fast)
        #expect(items.first?.scale == 1.5)
        #expect(Set(items.map(\.url)) == [fast, slow])
        #expect(interactor.playbackMode == .shuffle)
    }

    @Test("rippleConfig returns config from appStyle")
    func rippleConfigFromAppStyle() {
        let style = AppStyle(ripple: RippleStyle(enabled: true, idle: 3.0))
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
            $0.wallpaperUseCase = StubWallpaperUseCase()
        } operation: {
            WallpaperInteractorImpl()
        }

        #expect(interactor.rippleConfig.enabled == true)
        #expect(interactor.rippleConfig.idle == 3.0)
    }

    @Test("systemSleepChanges emits .willSleep on NSWorkspace sleep notification")
    func emitsWillSleep() async {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
            $0.wallpaperUseCase = StubWallpaperUseCase()
        } operation: {
            WallpaperInteractorImpl()
        }

        final class Collector: @unchecked Sendable { var events: [SleepWakeEvent] = [] }
        let collector = Collector()
        let cancellable = interactor.systemSleepChanges.sink { collector.events.append($0) }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification, object: nil)

        let deadline = ContinuousClock.now + .seconds(1)
        while collector.events.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(collector.events.contains(.willSleep))
        cancellable.cancel()
    }

    @Test("systemSleepChanges emits .didWake on NSWorkspace wake notification")
    func emitsDidWake() async {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
            $0.wallpaperUseCase = StubWallpaperUseCase()
        } operation: {
            WallpaperInteractorImpl()
        }

        final class Collector: @unchecked Sendable { var events: [SleepWakeEvent] = [] }
        let collector = Collector()
        let cancellable = interactor.systemSleepChanges.sink { collector.events.append($0) }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidWakeNotification, object: nil)

        let deadline = ContinuousClock.now + .seconds(1)
        while collector.events.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(collector.events.contains(.didWake))
        cancellable.cancel()
    }
}
