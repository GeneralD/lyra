import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Stub

private struct StubWallpaperInteractor: WallpaperInteractor {
    var wallpaperState: WallpaperState = .init()
    var rippleConfig: RippleStyle = .init()

    func resolveWallpaper() async throws -> WallpaperState { wallpaperState }
}

private struct FailingWallpaperInteractor: WallpaperInteractor {
    var rippleConfig: RippleStyle = .init()

    func resolveWallpaper() async throws -> WallpaperState { throw StubError.resolveFailed }
}

private enum StubError: Error {
    case resolveFailed
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
    }
}
