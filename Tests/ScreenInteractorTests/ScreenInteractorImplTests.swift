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
import Testing

@testable import ScreenInteractor

// MARK: - Stub

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    var style: AppStyle = .init()
    var appStyle: AppStyle { style }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
}

// MARK: - Tests

@Suite("ScreenInteractor")
struct ScreenInteractorImplTests {

    @MainActor
    @Test("resolveLayout returns non-zero window frame from real screen")
    func resolveLayoutReturnsNonZeroFrame() {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
        } operation: {
            ScreenInteractorImpl()
        }

        let layout = interactor.resolveLayout()
        #expect(layout.windowFrame.width > 0)
        #expect(layout.windowFrame.height > 0)
    }

    @MainActor
    @Test("resolveLayout hostingFrame fits within windowFrame")
    func hostingFrameFitsInWindow() {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
        } operation: {
            ScreenInteractorImpl()
        }

        let layout = interactor.resolveLayout()
        #expect(layout.hostingFrame.width <= layout.windowFrame.width)
        #expect(layout.hostingFrame.height <= layout.windowFrame.height)
    }

    @MainActor
    @Test("default screenSelector is .main")
    func defaultScreenSelectorIsMain() {
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase()
        } operation: {
            ScreenInteractorImpl()
        }

        #expect(interactor.screenSelector == .main)
    }

    @MainActor
    @Test("screenSelector reflects config value")
    func screenSelectorReflectsConfig() {
        let style = AppStyle(screen: .largest)
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
        } operation: {
            ScreenInteractorImpl()
        }

        #expect(interactor.screenSelector == .largest)
    }

    @MainActor
    @Test("out-of-range index falls back to valid screen — no crash")
    func outOfRangeIndexDoesNotCrash() {
        let style = AppStyle(screen: .index(999))
        let interactor = withDependencies {
            $0.configUseCase = StubConfigUseCase(style: style)
        } operation: {
            ScreenInteractorImpl()
        }

        let layout = interactor.resolveLayout()
        #expect(layout.windowFrame.width > 0, "fallback screen should have non-zero width")
    }
}