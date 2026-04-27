@preconcurrency import AVFoundation
import Domain
import Foundation
import Testing

@testable import Presenters

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("WallpaperPlaybackController")
struct WallpaperPlaybackControllerTests {

    @Suite("play")
    struct Play {
        @MainActor
        @Test("creates a player lazily on first play")
        func createsPlayerLazily() async {
            let controller = WallpaperPlaybackController()
            #expect(controller.player == nil)

            await controller.play(
                item: ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4")))

            #expect(controller.player != nil)
        }

        @MainActor
        @Test("reuses the same player across item swaps")
        func reusesPlayerAcrossItems() async {
            let controller = WallpaperPlaybackController()
            await controller.play(
                item: ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4")))
            let first = controller.player

            await controller.play(
                item: ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4")))

            #expect(controller.player === first)
        }

        @MainActor
        @Test("stop releases the player and observers")
        func stopReleasesPlayer() async {
            let controller = WallpaperPlaybackController()
            await controller.play(
                item: ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"), end: 5.0))
            #expect(controller.player != nil)

            controller.stop()

            #expect(controller.player == nil)
        }

        @MainActor
        @Test("play after stop creates a fresh player")
        func playAfterStopRecreates() async {
            let controller = WallpaperPlaybackController()
            await controller.play(
                item: ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4")))
            let firstPlayer = controller.player

            controller.stop()
            await controller.play(
                item: ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4")))

            #expect(controller.player != nil)
            #expect(controller.player !== firstPlayer)
        }
    }

    @Suite("handleBoundary")
    struct HandleBoundary {
        @MainActor
        @Test("does nothing without an end time set")
        func noEndTimeNoFire() async {
            let controller = WallpaperPlaybackController()
            final class Counter: @unchecked Sendable { var count = 0 }
            let counter = Counter()
            controller.onAdvanceRequested = { counter.count += 1 }

            await controller.play(
                item: ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4")))

            controller.handleBoundary(at: CMTime(seconds: 100, preferredTimescale: 600))
            #expect(counter.count == 0)
        }

        @MainActor
        @Test("ignores times before the end boundary")
        func ignoresEarlyTimes() async {
            let controller = WallpaperPlaybackController()
            final class Counter: @unchecked Sendable { var count = 0 }
            let counter = Counter()
            controller.onAdvanceRequested = { counter.count += 1 }

            await controller.play(
                item: ResolvedWallpaperItem(
                    url: URL(fileURLWithPath: "/tmp/a.mp4"), start: 2.0, end: 5.0))

            controller.handleBoundary(at: CMTime(seconds: 4.9, preferredTimescale: 600))
            #expect(counter.count == 0)
        }

        @MainActor
        @Test("fires onAdvanceRequested when crossing the end boundary")
        func firesAtBoundary() async {
            let controller = WallpaperPlaybackController()
            final class Counter: @unchecked Sendable { var count = 0 }
            let counter = Counter()
            controller.onAdvanceRequested = { counter.count += 1 }

            await controller.play(
                item: ResolvedWallpaperItem(
                    url: URL(fileURLWithPath: "/tmp/a.mp4"), end: 5.0))

            controller.handleBoundary(at: CMTime(seconds: 5, preferredTimescale: 600))
            #expect(counter.count == 1)
        }

        @MainActor
        @Test("debounces multiple rapid fires until isSeeking is cleared")
        func debouncesMultipleFires() async {
            let controller = WallpaperPlaybackController()
            final class Counter: @unchecked Sendable { var count = 0 }
            let counter = Counter()
            controller.onAdvanceRequested = { counter.count += 1 }

            await controller.play(
                item: ResolvedWallpaperItem(
                    url: URL(fileURLWithPath: "/tmp/a.mp4"), end: 5.0))

            let seekEnd = CMTime(seconds: 5, preferredTimescale: 600)
            controller.handleBoundary(at: seekEnd)
            controller.handleBoundary(at: seekEnd)
            controller.handleBoundary(at: CMTime(seconds: 6, preferredTimescale: 600))

            #expect(counter.count == 1)
        }

        @MainActor
        @Test("re-fires on next boundary after a fresh play() resets isSeeking")
        func refiresAfterPlayResets() async {
            let controller = WallpaperPlaybackController()
            final class Counter: @unchecked Sendable { var count = 0 }
            let counter = Counter()
            controller.onAdvanceRequested = { counter.count += 1 }

            await controller.play(
                item: ResolvedWallpaperItem(
                    url: URL(fileURLWithPath: "/tmp/a.mp4"), end: 5.0))
            controller.handleBoundary(at: CMTime(seconds: 5, preferredTimescale: 600))
            #expect(counter.count == 1)

            await controller.play(
                item: ResolvedWallpaperItem(
                    url: URL(fileURLWithPath: "/tmp/b.mp4"), end: 5.0))
            controller.handleBoundary(at: CMTime(seconds: 5, preferredTimescale: 600))
            #expect(counter.count == 2)
        }
    }

    @Suite("handleItemEnd")
    struct HandleItemEnd {
        @MainActor
        @Test("fires onAdvanceRequested when not already seeking")
        func firesWhenIdle() async {
            let controller = WallpaperPlaybackController()
            final class Counter: @unchecked Sendable { var count = 0 }
            let counter = Counter()
            controller.onAdvanceRequested = { counter.count += 1 }

            await controller.play(
                item: ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4")))
            controller.handleItemEnd()

            #expect(counter.count == 1)
        }

        @MainActor
        @Test("respects isSeeking debounce when handleBoundary already fired")
        func respectsBoundaryDebounce() async {
            let controller = WallpaperPlaybackController()
            final class Counter: @unchecked Sendable { var count = 0 }
            let counter = Counter()
            controller.onAdvanceRequested = { counter.count += 1 }

            await controller.play(
                item: ResolvedWallpaperItem(
                    url: URL(fileURLWithPath: "/tmp/a.mp4"), end: 5.0))
            controller.handleBoundary(at: CMTime(seconds: 5, preferredTimescale: 600))
            controller.handleItemEnd()

            #expect(counter.count == 1)
        }
    }

    @Suite("loopCurrent")
    struct LoopCurrent {
        @MainActor
        @Test("clears isSeeking even when player is nil")
        func clearsSeekingWithoutPlayer() {
            let controller = WallpaperPlaybackController()
            // Force isSeeking = true via handleItemEnd path with no player
            controller.handleItemEnd()  // no-op without player but still flips isSeeking

            controller.loopCurrent()
            // Subsequent handleItemEnd should fire because isSeeking was reset.
            final class Counter: @unchecked Sendable { var count = 0 }
            let counter = Counter()
            controller.onAdvanceRequested = { counter.count += 1 }
            controller.handleItemEnd()

            #expect(counter.count == 1)
        }
    }
}
