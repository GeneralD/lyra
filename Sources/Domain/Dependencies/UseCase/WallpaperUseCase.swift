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

public protocol WallpaperUseCase: Sendable {
    func resolveWallpaper(value: String?, configDir: String) async throws -> URL?
}

public enum WallpaperUseCaseKey: TestDependencyKey {
    public static let testValue: any WallpaperUseCase = UnimplementedWallpaperUseCase()
}

extension DependencyValues {
    public var wallpaperUseCase: any WallpaperUseCase {
        get { self[WallpaperUseCaseKey.self] }
        set { self[WallpaperUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedWallpaperUseCase: WallpaperUseCase {
    func resolveWallpaper(value: String?, configDir: String) async throws -> URL? { nil }
}