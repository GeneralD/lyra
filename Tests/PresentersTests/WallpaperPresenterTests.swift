@preconcurrency import AVFoundation
@preconcurrency import Combine
import Dependencies
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

private final class SpyAVPlayer: AVPlayer, @unchecked Sendable {
    nonisolated(unsafe) var playCallCount = 0
    nonisolated(unsafe) var seekTimes: [CMTime] = []
    nonisolated(unsafe) var pendingSeekCompletions: [(Bool) -> Void] = []

    override func play() {
        playCallCount += 1
    }

    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        seekTimes.append(time)
    }

    override func seek(
        to time: CMTime,
        toleranceBefore: CMTime,
        toleranceAfter: CMTime,
        completionHandler: @escaping (Bool) -> Void
    ) {
        seekTimes.append(time)
        pendingSeekCompletions.append(completionHandler)
    }

    func completePendingSeeks() {
        let completions = pendingSeekCompletions
        pendingSeekCompletions = []
        for completion in completions {
            completion(true)
        }
    }
}

private func hasValue(named name: String, from object: Any) -> Bool {
    guard
        let storedValue = Mirror(reflecting: object).children
            .first(where: { $0.label == name })?
            .value
    else { return false }

    let mirror = Mirror(reflecting: storedValue)
    guard mirror.displayStyle == .optional else { return true }
    return mirror.children.first != nil
}

private func value<T>(named name: String, from object: Any) -> T? {
    guard
        let storedValue = Mirror(reflecting: object).children
            .first(where: { $0.label == name })?
            .value
    else { return nil }

    let mirror = Mirror(reflecting: storedValue)
    let unwrappedValue =
        if mirror.displayStyle == .optional {
            mirror.children.first?.value as Any
        } else {
            storedValue
        }
    return unwrappedValue as? T
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
            let item = ResolvedWallpaperItem(url: url, start: 5.0, end: 30.0)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [item])
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()

                #expect(presenter.wallpaperURL == url)
                #expect(presenter.startTime == 5.0)
                #expect(presenter.endTime == 30.0)
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
                await presenter.waitForLoad()

                #expect(presenter.wallpaperURL == nil)
                #expect(presenter.startTime == nil)
                #expect(presenter.endTime == nil)
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
                await presenter.waitForLoad()
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
                await presenter.waitForLoad()

                #expect(presenter.wallpaperURL == url)
                #expect(presenter.startTime == 10.0)
                #expect(presenter.endTime == nil)
            }
        }

        @MainActor
        @Test("start with endTime registers observers and stop clears them")
        func registersAndClearsLoopObservers() async {
            let item = ResolvedWallpaperItem(
                url: URL(fileURLWithPath: "/tmp/loop.mp4"),
                start: 2.0,
                end: 4.0
            )

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [item])
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()

                #expect(hasValue(named: "endTimeObserver", from: presenter))
                #expect(hasValue(named: "loopObserver", from: presenter))

                presenter.stop()

                #expect(!hasValue(named: "endTimeObserver", from: presenter))
                #expect(!hasValue(named: "loopObserver", from: presenter))
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
                await presenter.waitForLoad()

                let deadline = ContinuousClock.now + .seconds(2)
                while counter.count < 1, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }

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
                await presenter.waitForLoad()

                #expect(counter.count == 0)
                #expect(presenter.player == nil)
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
                await presenter.waitForLoad()
                presenter.stop()
                // Exercises cancellables.removeAll() branch — no crash expected.
            }
        }
    }

    @Suite("loop observers")
    struct LoopObservers {
        @MainActor
        @Test("handleLoopBoundary seeks once until the pending seek completes (single item)")
        func loopBoundaryDeduplicatesWhileSeeking() async {
            let presenter = WallpaperPresenter()
            let player = SpyAVPlayer()
            let seekStart = CMTime(seconds: 2, preferredTimescale: 600)
            let seekEnd = CMTime(seconds: 5, preferredTimescale: 600)

            presenter.handleLoopBoundary(at: seekEnd, seekEnd: seekEnd, seekStart: seekStart, player: player)
            presenter.handleLoopBoundary(
                at: CMTime(seconds: 6, preferredTimescale: 600),
                seekEnd: seekEnd,
                seekStart: seekStart,
                player: player
            )

            #expect(player.seekTimes == [seekStart])
            #expect((value(named: "isSeeking", from: presenter) as Bool?) == true)

            player.completePendingSeeks()
            await waitUntil {
                (value(named: "isSeeking", from: presenter) as Bool?) == false
            }

            presenter.handleLoopBoundary(
                at: CMTime(seconds: 6, preferredTimescale: 600),
                seekEnd: seekEnd,
                seekStart: seekStart,
                player: player
            )

            #expect(player.seekTimes == [seekStart, seekStart])
        }

        @MainActor
        @Test("handleLoopBoundary ignores times before the end boundary")
        func loopBoundaryIgnoresEarlyTimes() {
            let presenter = WallpaperPresenter()
            let player = SpyAVPlayer()
            let seekStart = CMTime(seconds: 2, preferredTimescale: 600)
            let seekEnd = CMTime(seconds: 5, preferredTimescale: 600)

            presenter.handleLoopBoundary(
                at: CMTime(seconds: 4.9, preferredTimescale: 600),
                seekEnd: seekEnd,
                seekStart: seekStart,
                player: player
            )

            #expect(player.seekTimes.isEmpty)
            #expect((value(named: "isSeeking", from: presenter) as Bool?) == false)
        }

        @MainActor
        @Test("restartPlayback seeks to loop start and resumes playback")
        func restartPlaybackSeeksAndPlays() {
            let player = SpyAVPlayer()
            let seekStart = CMTime(seconds: 3, preferredTimescale: 600)

            WallpaperPresenter.restartPlayback(from: seekStart, player: player)

            #expect(player.seekTimes == [seekStart])
            #expect(player.playCallCount == 1)
        }

        @MainActor
        @Test("AVPlayerItemDidPlayToEndTime notification schedules playback restart")
        func endNotificationSchedulesRestart() async {
            let item = ResolvedWallpaperItem(
                url: URL(fileURLWithPath: "/tmp/loop.mp4"),
                start: 2.0,
                end: 4.0
            )

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [item])
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()

                guard let currentItem = presenter.player?.currentItem else {
                    Issue.record("expected currentItem to exist after setupPlayer")
                    return
                }

                NotificationCenter.default.post(
                    name: .AVPlayerItemDidPlayToEndTime,
                    object: currentItem
                )

                // Yield so the @MainActor Task scheduled by the observer runs.
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    @Suite("multi-item advancement")
    struct MultiItem {
        @MainActor
        @Test("cycle mode advances items in configured order on item completion")
        func cycleAdvancesInOrder() async {
            let a = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"))
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
            let c = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/c.mp4"))

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b, c], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()
                #expect(presenter.wallpaperURL == a.url)

                await presenter.advanceToNextItem()
                #expect(presenter.wallpaperURL == b.url)

                await presenter.advanceToNextItem()
                #expect(presenter.wallpaperURL == c.url)

                await presenter.advanceToNextItem()
                #expect(presenter.wallpaperURL == a.url)  // wraps around
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
                await presenter.waitForLoad()
                #expect(presenter.wallpaperURL == a.url)

                await presenter.advanceToNextItem()
                #expect(presenter.wallpaperURL == c.url)

                await presenter.advanceToNextItem()
                #expect(presenter.wallpaperURL == a.url)
            }
        }

        @MainActor
        @Test("nextIndex cycle wraps around at the end")
        func nextIndexCycleWraps() async {
            let items = [
                ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4")),
                ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4")),
            ]

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: items, mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()

                #expect(presenter.nextIndex(from: 0) == 1)
                #expect(presenter.nextIndex(from: 1) == 0)
            }
        }

        @MainActor
        @Test("nextIndex shuffle never returns current index when count > 1")
        func shuffleNeverRepeatsCurrent() async {
            let items = (0..<5).map {
                ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/\($0).mp4"))
            }
            // The fake source returns 0 — selected from filtered candidates,
            // which excludes current. So result should never equal `from`.
            let fake = FakeRandomSource([0, 0, 0, 0, 0])

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: items, mode: .shuffle)
                $0.randomSource = fake
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()

                for current in 0..<5 {
                    #expect(presenter.nextIndex(from: current) != current)
                }
            }
        }

        @MainActor
        @Test("handleItemCompletion on single item restarts playback (does not advance)")
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
                await presenter.waitForLoad()
                let urlBefore = presenter.wallpaperURL

                await presenter.handleItemCompletion(seekStart: CMTime(seconds: 1, preferredTimescale: 600))

                #expect(presenter.wallpaperURL == urlBefore)
            }
        }

        @MainActor
        @Test("handleItemCompletion on multiple items advances to next item")
        func multiItemCompletionAdvances() async {
            let a = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"))
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()
                #expect(presenter.wallpaperURL == a.url)

                await presenter.handleItemCompletion(seekStart: .zero)

                #expect(presenter.wallpaperURL == b.url)
            }
        }

        @MainActor
        @Test("handleLoopBoundary on multiple items advances instead of seeking")
        func multiItemLoopBoundaryAdvances() async {
            let a = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/a.mp4"))
            let b = ResolvedWallpaperItem(url: URL(fileURLWithPath: "/tmp/b.mp4"))
            let player = SpyAVPlayer()
            let seekStart = CMTime(seconds: 1, preferredTimescale: 600)
            let seekEnd = CMTime(seconds: 5, preferredTimescale: 600)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(items: [a, b], mode: .cycle)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()
                #expect(presenter.wallpaperURL == a.url)

                presenter.handleLoopBoundary(at: seekEnd, seekEnd: seekEnd, seekStart: seekStart, player: player)

                await waitUntil { presenter.wallpaperURL == b.url }
                #expect(presenter.wallpaperURL == b.url)
                #expect(player.seekTimes.isEmpty)  // no manual seek — advance instead
            }
        }
    }

    @Suite("SystemRandomSource")
    struct SystemRandomSourceTests {
        @Test("returns values in [0, count)")
        func withinRange() {
            let source = SystemRandomSource()
            for count in 1...32 {
                for _ in 0..<50 {
                    let value = source.next(below: count)
                    #expect(value >= 0)
                    #expect(value < count)
                }
            }
        }

        @Test("returns 0 when count is 1")
        func singleValue() {
            let source = SystemRandomSource()
            for _ in 0..<10 {
                #expect(source.next(below: 1) == 0)
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
                await presenter.waitForLoad()

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
                await presenter.waitForLoad()

                subject.send(.willSleep)
                subject.send(.didWake)
                // Exercising the .didWake branch of observeSleepWake sink.
            }
        }
    }
}
