import CoreGraphics
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presentation

// MARK: - Stub

private struct StubScreenInteractor: ScreenInteractor {
    var screenSelector: ScreenSelector = .main
    var layoutResult: ScreenLayout = .init()

    func resolveLayout(hasWallpaper: Bool) async -> ScreenLayout { layoutResult }
}

// MARK: - Tests

@Suite("AppPresenter")
struct AppPresenterTests {

    @Suite("resolveFrames")
    struct ResolveFrames {
        @MainActor
        @Test("sets layout when hasWallpaper is true")
        func setsLayoutWithWallpaper() async {
            let expectedLayout = ScreenLayout(
                windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                hostingFrame: CGRect(x: 10, y: 10, width: 1900, height: 1060),
                screenOrigin: CGPoint(x: 0, y: 0)
            )

            await withDependencies {
                $0.screenInteractor = StubScreenInteractor(layoutResult: expectedLayout)
            } operation: {
                let presenter = AppPresenter()
                presenter.hasWallpaper = true
                await presenter.resolveFrames()

                #expect(presenter.hasWallpaper == true)
                #expect(presenter.layout.windowFrame == expectedLayout.windowFrame)
            }
        }

        @MainActor
        @Test("sets layout when hasWallpaper is false")
        func setsLayoutWithoutWallpaper() async {
            await withDependencies {
                $0.screenInteractor = StubScreenInteractor()
            } operation: {
                let presenter = AppPresenter()
                await presenter.resolveFrames()

                #expect(presenter.hasWallpaper == false)
                #expect(presenter.layout.windowFrame == .zero)
            }
        }
    }
}
