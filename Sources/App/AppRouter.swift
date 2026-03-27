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

import Presenters
import Views

/// Wireframe: creates Presenters, builds window, manages lifecycle.
@MainActor
public final class AppRouter {
    private let appPresenter = AppPresenter()
    private let headerPresenter = HeaderPresenter()
    private let lyricsPresenter = LyricsPresenter()
    private let wallpaperPresenter = WallpaperPresenter()
    private var ripplePresenter: RipplePresenter?

    private var appWindow: AppWindow?
    private var displayLinkDriver: DisplayLinkDriver?

    public init() {}

    public func start() {
        appPresenter.start()
        let ripple = RipplePresenter(screenOrigin: appPresenter.layout.screenOrigin)
        ripplePresenter = ripple

        headerPresenter.start()
        lyricsPresenter.start()
        ripple.start()
        wallpaperPresenter.start()

        let window = AppWindow(
            appPresenter: appPresenter,
            wallpaperPresenter: wallpaperPresenter,
            headerPresenter: headerPresenter,
            lyricsPresenter: lyricsPresenter,
            ripplePresenter: ripple
        )
        appWindow = window

        let driver = DisplayLinkDriver { [weak self] in
            self?.ripplePresenter?.idle()
            self?.lyricsPresenter.updateActiveLineTick()
        }
        self.displayLinkDriver = driver
        driver.start(in: window)
    }

    public func stop() {
        headerPresenter.stop()
        lyricsPresenter.stop()
        wallpaperPresenter.stop()
        ripplePresenter?.stop()
        displayLinkDriver?.stop()
        appWindow?.orderOut(nil)
        appWindow?.close()
        appWindow = nil
    }
}