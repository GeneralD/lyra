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
import Foundation

public protocol WallpaperInteractor: Sendable {
    func resolveWallpaper() async throws -> WallpaperState
    var rippleConfig: RippleStyle { get }
}

public enum WallpaperInteractorKey: TestDependencyKey {
    public static let testValue: any WallpaperInteractor = UnimplementedWallpaperInteractor()
}

extension DependencyValues {
    public var wallpaperInteractor: any WallpaperInteractor {
        get { self[WallpaperInteractorKey.self] }
        set { self[WallpaperInteractorKey.self] = newValue }
    }
}

private struct UnimplementedWallpaperInteractor: WallpaperInteractor {
    func resolveWallpaper() async throws -> WallpaperState {
        WallpaperState()
    }
    var rippleConfig: RippleStyle { .init() }
}