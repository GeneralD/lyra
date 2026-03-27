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

public struct WallpaperInteractorImpl {
    @Dependency(\.configUseCase) private var configService
    @Dependency(\.wallpaperUseCase) private var wallpaperService

    public init() {}
}

extension WallpaperInteractorImpl: WallpaperInteractor {
    public func resolveWallpaper() async throws -> WallpaperState {
        let appStyle = configService.appStyle
        guard let wallpaper = appStyle.wallpaper else {
            return WallpaperState()
        }
        let configDir = appStyle.configDir ?? FileManager.default.homeDirectoryForCurrentUser.path
        let url = try await wallpaperService.resolveWallpaper(
            value: wallpaper.location, configDir: configDir
        )
        return WallpaperState(url: url, start: wallpaper.start, end: wallpaper.end)
    }

    public var rippleConfig: RippleStyle {
        configService.appStyle.ripple
    }
}