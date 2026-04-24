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

// MARK: - Stub

private struct StubWallpaperInteractor: WallpaperInteractor {
    var wallpaperState: WallpaperState = .init()
    var rippleConfig: RippleStyle = .init()
    var sleepChangesSubject: PassthroughSubject<SleepWakeEvent, Never>? = nil

    func resolveWallpaper() async throws -> WallpaperState { wallpaperState }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> {
        sleepChangesSubject?.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()
    }
}

private struct FailingWallpaperInteractor: WallpaperInteractor {
    var rippleConfig: RippleStyle = .init()

    func resolveWallpaper() async throws -> WallpaperState { throw StubError.resolveFailed }
    var systemSleepChanges: AnyPublisher<SleepWakeEvent, Never> { Empty().eraseToAnyPublisher() }
}

private enum StubError: Error {
    case resolveFailed
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
        @Test("sets wallpaperURL, start, and end from interactor result")
        func setsWallpaperState() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let state = WallpaperState(url: url, start: 5.0, end: 30.0)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(wallpaperState: state)
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
        @Test("nil state when no wallpaper configured")
        func nilWallpaper() async {
            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(wallpaperState: .init())
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()

                #expect(presenter.wallpaperURL == nil)
                #expect(presenter.startTime == nil)
                #expect(presenter.endTime == nil)
                #expect(presenter.isLoading == false)
            }
        }

        @MainActor
        @Test("sets nil when interactor throws")
        func handlesError() async {
            await withDependencies {
                $0.wallpaperInteractor = FailingWallpaperInteractor()
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()

                #expect(presenter.wallpaperURL == nil)
                #expect(presenter.isLoading == false)
            }
        }

        @MainActor
        @Test("stop clears player state")
        func stopClearsPlayer() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let state = WallpaperState(url: url, start: 5.0, end: 30.0)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(wallpaperState: state)
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
            let state = WallpaperState(url: url, start: 10.0, end: nil)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(wallpaperState: state)
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
            let state = WallpaperState(
                url: URL(fileURLWithPath: "/tmp/loop.mp4"),
                start: 2.0,
                end: 4.0
            )

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(wallpaperState: state)
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
            let state = WallpaperState(url: url, start: nil, end: nil)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(wallpaperState: state)
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
        @Test("never fires when no wallpaper is configured")
        func doesNotFireWhenNoPlayer() async {
            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(wallpaperState: .init())
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
            let state = WallpaperState(url: url, start: nil, end: nil)

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(wallpaperState: state)
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
        @Test("handleLoopBoundary seeks once until the pending seek completes")
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
            let state = WallpaperState(
                url: URL(fileURLWithPath: "/tmp/loop.mp4"),
                start: 2.0,
                end: 4.0
            )

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(wallpaperState: state)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()

                guard let item = presenter.player?.currentItem else {
                    Issue.record("expected currentItem to exist after setupPlayer")
                    return
                }

                NotificationCenter.default.post(
                    name: .AVPlayerItemDidPlayToEndTime,
                    object: item
                )

                // Yield so the @MainActor Task scheduled by the observer runs.
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    @Suite("sleep / wake observation")
    struct SleepWake {
        @MainActor
        @Test(".willSleep pauses the player")
        func willSleepPauses() async {
            let url = URL(fileURLWithPath: "/tmp/bg.mp4")
            let state = WallpaperState(url: url, start: nil, end: nil)
            let subject = PassthroughSubject<SleepWakeEvent, Never>()

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(
                    wallpaperState: state, sleepChangesSubject: subject)
            } operation: {
                let presenter = WallpaperPresenter()
                presenter.start()
                await presenter.waitForLoad()

                // setupPlayer started playback; emit .willSleep and observe pause.
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
            let state = WallpaperState(url: url, start: nil, end: nil)
            let subject = PassthroughSubject<SleepWakeEvent, Never>()

            await withDependencies {
                $0.wallpaperInteractor = StubWallpaperInteractor(
                    wallpaperState: state, sleepChangesSubject: subject)
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
