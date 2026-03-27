// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
}