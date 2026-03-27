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

// MARK: - Helpers

@MainActor
private func waitUntilLoaded(_ presenter: WallpaperPresenter, timeout: Duration = .seconds(2)) async {
    let deadline = ContinuousClock.now + timeout
    while presenter.isLoading, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
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
                await waitUntilLoaded(presenter)

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
                await waitUntilLoaded(presenter)

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
                await waitUntilLoaded(presenter)

                #expect(presenter.wallpaperURL == nil)
                #expect(presenter.isLoading == false)
            }
        }
    }
}
