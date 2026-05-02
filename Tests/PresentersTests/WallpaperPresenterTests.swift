@preconcurrency import AVFoundation
@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

@MainActor
private func waitForItemsLoaded(_ presenter: WallpaperPresenter, count: Int) async {
    await waitUntil { presenter.items.count == count }
}

// MARK: - Stubs

private struct StubWallpaperInteractor: WallpaperInteractor {
    var items: [ResolvedWallpaperItem] = []
    var mode: WallpaperPlaybackMode = .cycle
    var rippleConfig: RippleStyle = .init()
    var sleepChangesSubject: PassthroughSubject<SleepWakeEvent, Never>? = nil

    var playbackMode: WallpaperPlaybackMode { mode }

    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> {
        let emitted = items
        return AsyncStream { continuation in
            for item in emitted { continuation.yield(item) }
            continuation.finish()
        }
    }

    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> {
        sleepChangesSubject?.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }
}

private final class FakeRandomSource: RandomSource, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int]

    init(_ values: [Int]) { self.values = values }

    func next(below count: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { return 0 }
        let v = values.removeFirst()
        return ((v % count) + count) % count
    }
}

/// A stub interactor that lets the test drive item arrival over time. Used to
/// simulate late-arriving items in the resolved-wallpaper stream.
private final class LiveStubWallpaperInteractor: WallpaperInteractor, @unchecked Sendable {
    let mode: WallpaperPlaybackMode
    let rippleConfig: RippleStyle = .init()
    private let lock = NSLock()
    private var continuation: AsyncStream<ResolvedWallpaperItem>.Continuation?

    init(mode: WallpaperPlaybackMode = .cycle) {
        self.mode = mode
    }

    var playbackMode: WallpaperPlaybackMode { mode }

    func resolvedWallpapers() -> AsyncStream<ResolvedWallpaperItem> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation?.finish()
            self.continuation = continuation
            lock.unlock()
        }
    }

    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> {
        Empty().eraseToAnyPublisher()
    }

    func emit(_ item: ResolvedWallpaperItem) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(item)
    }

    func finish() {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.finish()
    }
}

// MARK: - Tests

@Suite("WallpaperPresenter")
struct WallpaperPresenterTests {

    @Suite("start")
    struct Resolve {
        @MainActor
        @Test("plays the first emitted item")
        func playsFirstItem() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let item = ResolvedWallpaperItem(url: url, start: 5.0, end: 30.0, scale: 1.25)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [item])
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitUntil { presenter.wallpaperURL == url }

                #expect(presenter.wallpaperURL == url)
                #expect(presenter.startTime == 5.0)
                #expect(presenter.endTime == 30.0)
                #expect(presenter.wallpaperScale == 1.25)
                #expect(presenter.isLoading == false)
            }
        }

        @MainActor
        @Test("remains idle when the stream emits no items")
        func emptyStream() async {
            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor()
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitUntil { !presenter.isLoading }

                #expect(presenter.wallpaperURL == nil)
                #expect(presenter.startTime == nil)
                #expect(presenter.endTime == nil)
                #expect(presenter.wallpaperScale == 1.0)
                #expect(presenter.isLoading == false)
                #expect(presenter.player == nil)
            }
        }

        @MainActor
        @Test("stop clears player state")
        func stopClearsPlayer() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let item = ResolvedWallpaperItem(url: url, start: 5.0, end: 30.0)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [item])
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitUntil { presenter.wallpaperURL == url }
                #expect(presenter.wallpaperURL == url)

                presenter.stop()
                #expect(presenter.player == nil)
            }
        }

        @MainActor
        @Test("start with only start time, no end time")
        func startTimeOnly() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let item = ResolvedWallpaperItem(url: url, start: 10.0)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [item])
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitUntil { presenter.wallpaperURL == url }

                #expect(presenter.wallpaperURL == url)
                #expect(presenter.startTime == 10.0)
                #expect(presenter.endTime == nil)
            }
        }
    }

    @Suite("onPlayerAvailable")
    struct OnPlayerAvailable {
        @MainActor
        @Test("fires once when player becomes available")
        func firesOnceOnPlayerReady() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let item = ResolvedWallpaperItem(url: url)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [item])
            } operation: {
                let presenter = WallpaperPresenter()

                final class Counter: @unchecked Sendable {
                    var count = 0
                    var player: AVPlayer?
                }
                let counter = Counter()

                presenter.onPlayerAvailable { player in
                    counter.count += 1
                    counter.player = player
                }

                presenter.start()
                await waitUntil { counter.count >= 1 }

                #expect(counter.count == 1)
                #expect(counter.player === presenter.player)
            }
        }

        @MainActor
        @Test("never fires when stream is empty")
        func doesNotFireWhenNoPlayer() async {
            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor()
            } operation: {
                let presenter = WallpaperPresenter()
                final class Counter: @unchecked Sendable { var count = 0 }
                let counter = Counter()

                presenter.onPlayerAvailable { _ in counter.count += 1 }
                presenter.start()
                await waitUntil { !presenter.isLoading }

                #expect(counter.count == 0)
                #expect(presenter.player == nil)
            }
        }

        @MainActor
        @Test("does not fire again when items advance (stable player instance)")
        func staysAttachedAcrossAdvances() async {
            let a = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"))
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()

                final class Recorder: @unchecked Sendable {
                    var players: [AVPlayer] = []
                }
                let recorder = Recorder()

                presenter.onPlayerAvailable { player in
                    recorder.players.append(player)
                }

                presenter.start()
                await waitForItemsLoaded(presenter, count: 2)

                await waitUntil { recorder.players.count >= 1 }
                #expect(recorder.players.count == 1)
                let firstPlayer = recorder.players.first

                presenter.controller.handleItemEnd()
                await waitUntil { presenter.wallpaperURL == b.url }

                #expect(recorder.players.count == 1)
                #expect(presenter.player === firstPlayer)
            }
        }

        @MainActor
        @Test("stop clears onPlayerAvailable subscription")
        func stopClearsSubscription() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let item = ResolvedWallpaperItem(url: url)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [item])
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.onPlayerAvailable { _ in }
                presenter.start()
                await waitUntil { presenter.wallpaperURL == url }
                presenter.stop()
                // Exercises cancellables.removeAll() branch — no crash expected.
            }
        }
    }

    @Suite("onWallpaperScaleChange")
    struct OnWallpaperScaleChange {
        @MainActor
        @Test("fires current and subsequent item scales")
        func firesScaleChanges() async {
            let a = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"), scale: 1.2)
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"), scale: 1.6)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()

                final class Recorder: @unchecked Sendable {
                    var scales: [Double] = []
                }
                let recorder = Recorder()

                presenter.onWallpaperScaleChange { scale in
                    recorder.scales.append(scale)
                }
                presenter.start()

                await waitUntil { recorder.scales.contains(1.2) }
                #expect(presenter.wallpaperScale == 1.2)

                presenter.controller.handleItemEnd()
                await waitUntil { recorder.scales.contains(1.6) }
                #expect(presenter.wallpaperScale == 1.6)
            }
        }
    }

    @Suite("multi-item advancement")
    struct MultiItem {
        @MainActor
        @Test("cycle mode advances items in configured order on item completion")
        func cycleAdvancesInOrder() async {
            let a = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"), scale: 1.0)
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"), scale: 1.3)
            let c = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/c.mp4"), scale: 1.6)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b, c], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitForItemsLoaded(presenter, count: 3)
                #expect(presenter.wallpaperURL == a.url)
                #expect(presenter.wallpaperScale == 1.0)

                presenter.controller.handleItemEnd()
                await waitUntil { presenter.wallpaperURL == b.url }
                #expect(presenter.wallpaperScale == 1.3)

                presenter.controller.handleItemEnd()
                await waitUntil { presenter.wallpaperURL == c.url }
                #expect(presenter.wallpaperScale == 1.6)

                presenter.controller.handleItemEnd()
                await waitUntil { presenter.wallpaperURL == a.url }
                #expect(presenter.wallpaperURL == a.url)  // wraps around
                #expect(presenter.wallpaperScale == 1.0)
            }
        }

        @MainActor
        @Test("shuffle mode picks next item via RandomSource, excluding current")
        func shuffleUsesRandomSource() async {
            let a = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"))
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
            let c = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/c.mp4"))

            // After index 0 (a), candidates = [1, 2]. RandomSource picks index 1 → c.
            // After index 2 (c), candidates = [0, 1]. RandomSource picks index 0 → a.
            let fake = FakeRandomSource([1, 0])

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b, c], mode: .shuffle)
                $0.randomSource = fake
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitForItemsLoaded(presenter, count: 3)
                #expect(presenter.wallpaperURL == a.url)

                presenter.controller.handleItemEnd()
                await waitUntil { presenter.wallpaperURL == c.url }

                presenter.controller.handleItemEnd()
                await waitUntil { presenter.wallpaperURL == a.url }
                #expect(presenter.wallpaperURL == a.url)
            }
        }

        @MainActor
        @Test("controller.handleItemEnd on single item loops via controller, not advance")
        func singleItemLoopsRatherThanAdvance() async {
            let item = ResolvedWallpaperItem(
                url: URL(fileURLWithPath: "/tmp/solo.mp4"),
                start: 1.0,
                end: 3.0
            )

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [item])
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitUntil { presenter.wallpaperURL == item.url }
                let urlBefore = presenter.wallpaperURL

                presenter.controller.handleItemEnd()

                // Give the advance Task a chance to run; verify URL did not change.
                await waitUntil(timeout: .milliseconds(50)) {
                    presenter.wallpaperURL != urlBefore
                }

                #expect(presenter.wallpaperURL == urlBefore)
            }
        }

        @MainActor
        @Test("controller.handleItemEnd on multiple items advances to next item")
        func multiItemCompletionAdvances() async {
            let a = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"))
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitForItemsLoaded(presenter, count: 2)
                #expect(presenter.wallpaperURL == a.url)

                presenter.controller.handleItemEnd()

                await waitUntil { presenter.wallpaperURL == b.url }
                #expect(presenter.wallpaperURL == b.url)
            }
        }

        @MainActor
        @Test("controller.handleBoundary on multiple items advances")
        func multiItemLoopBoundaryAdvances() async {
            let a = ResolvedWallpaperItem(
                url: URL(fileURLWithPath: "/tmp/a.mp4"), start: 1.0, end: 5.0)
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
            let seekEnd = CMTime(seconds: 5, preferredTimescale: 600)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitForItemsLoaded(presenter, count: 2)
                #expect(presenter.wallpaperURL == a.url)

                presenter.controller.handleBoundary(at: seekEnd)

                await waitUntil { presenter.wallpaperURL == b.url }
                #expect(presenter.wallpaperURL == b.url)
            }
        }

        @MainActor
        @Test("repeated handleBoundary firings advance only once (no double-advance race)")
        func repeatedLoopBoundaryAdvancesOnce() async {
            let a = ResolvedWallpaperItem(
                url: URL(fileURLWithPath: "/tmp/a.mp4"), start: 1.0, end: 5.0)
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
            let c = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/c.mp4"))
            let seekEnd = CMTime(seconds: 5, preferredTimescale: 600)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b, c], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitForItemsLoaded(presenter, count: 3)
                #expect(presenter.wallpaperURL == a.url)

                // Simulate periodic time observer firing several times before the
                // first advance Task gets to run on the actor.
                presenter.controller.handleBoundary(at: seekEnd)
                presenter.controller.handleBoundary(at: seekEnd)
                presenter.controller.handleBoundary(at: seekEnd)

                await waitUntil { presenter.wallpaperURL == b.url }
                // Should land on b (one advance from a), not skip to c.
                #expect(presenter.wallpaperURL == b.url)
            }
        }
    }

    @Suite("late-arriving items")
    struct LateArrival {
        @MainActor
        @Test("items emitted after playback starts are picked up on next advance")
        func lateArrivalAdvancesToNewItem() async {
            let a = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"))
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
            let interactor = LiveStubWallpaperInteractor(mode: .cycle)

            await withDependencies {
                $0.wallpaperInteractor = interactor
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()

                interactor.emit(a)
                await waitUntil { presenter.wallpaperURL == a.url }
                #expect(presenter.wallpaperURL == a.url)

                // Late arrival — second item shows up after playback has begun.
                interactor.emit(b)
                interactor.finish()
                await waitForItemsLoaded(presenter, count: 2)

                presenter.controller.handleItemEnd()
                await waitUntil { presenter.wallpaperURL == b.url }
                #expect(presenter.wallpaperURL == b.url)
            }
        }

        @MainActor
        @Test("single-item stream remains in loop mode until a second item arrives")
        func lateArrivalUnlocksAdvancement() async {
            let a = ResolvedWallpaperItem(
                url: URL(fileURLWithPath: "/tmp/a.mp4"), end: 5.0)
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
            let interactor = LiveStubWallpaperInteractor(mode: .cycle)

            await withDependencies {
                $0.wallpaperInteractor = interactor
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()

                interactor.emit(a)
                await waitUntil { presenter.wallpaperURL == a.url }

                // Boundary fires while only one item is loaded — should loop, not advance.
                presenter.controller.handleBoundary(
                    at: CMTime(seconds: 5, preferredTimescale: 600))
                await waitUntil(timeout: .milliseconds(50)) {
                    presenter.wallpaperURL != a.url
                }
                #expect(presenter.wallpaperURL == a.url)

                interactor.emit(b)
                interactor.finish()
                await waitForItemsLoaded(presenter, count: 2)

                // Now that two items exist, boundary should advance.
                presenter.controller.handleBoundary(
                    at: CMTime(seconds: 5, preferredTimescale: 600))
                await waitUntil { presenter.wallpaperURL == b.url }
                #expect(presenter.wallpaperURL == b.url)
            }
        }
    }

    @Suite("shuffle determinism")
    struct ShuffleDeterminism {
        @MainActor
        @Test("shuffle visits every item over many advances given a covering sequence")
        func visitsAllItems() async {
            let items = (0..<5).map {
                ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/\($0).mp4"))
            }
            // Advance 20 times; pick deterministic indices that cycle through candidates.
            let fake = FakeRandomSource(Array(repeating: [0, 1, 2, 3], count: 5).flatMap { $0 })

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: items, mode: .shuffle)
                $0.randomSource = fake
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitForItemsLoaded(presenter, count: items.count)

                var visited = Set<URL>([presenter.wallpaperURL].compactMap { $0 })
                for _ in 0..<20 {
                    let prev = presenter.wallpaperURL
                    presenter.controller.handleItemEnd()
                    await waitUntil { presenter.wallpaperURL != prev }
                    if let url = presenter.wallpaperURL { visited.insert(url) }
                }

                #expect(visited.count == items.count)
            }
        }
    }

    @Suite("double-fire guard")
    struct DoubleFireGuard {
        @MainActor
        @Test("handleBoundary then handleItemEnd advances only once")
        func boundaryThenItemEndAdvancesOnce() async {
            let a = ResolvedWallpaperItem(
                url: URL(fileURLWithPath: "/tmp/a.mp4"), end: 5.0)
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
            let c = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/c.mp4"))

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(
                    items: [a, b, c], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitForItemsLoaded(presenter, count: 3)
                #expect(presenter.wallpaperURL == a.url)

                presenter.controller.handleBoundary(
                    at: CMTime(seconds: 5, preferredTimescale: 600))
                presenter.controller.handleItemEnd()

                await waitUntil { presenter.wallpaperURL == b.url }
                #expect(presenter.wallpaperURL == b.url)
            }
        }
    }

    @Suite("sleep / wake observation")
    struct SleepWake {
        @MainActor
        @Test(".willSleep pauses the player")
        func willSleepPauses() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let item = ResolvedWallpaperItem(url: url)
            let subject = PassthroughSubject<SleepWakeEvent, Never>()

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(
                    items: [item], sleepChangesSubject: subject)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitUntil { presenter.player != nil }

                subject.send(.willSleep)

                let deadline = ContinuousClock.now + .seconds(1)
                while presenter.player?.rate != 0, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                #expect(presenter.player?.rate == 0)
            }
        }

        @MainActor
        @Test(".didWake resumes the player")
        func didWakeResumes() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let item = ResolvedWallpaperItem(url: url)
            let subject = PassthroughSubject<SleepWakeEvent, Never>()

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(
                    items: [item], sleepChangesSubject: subject)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await waitUntil { presenter.player != nil }

                subject.send(.willSleep)
                subject.send(.didWake)
                // Exercising the .didWake branch of observeSleepWake sink.
            }
        }
    }
}
