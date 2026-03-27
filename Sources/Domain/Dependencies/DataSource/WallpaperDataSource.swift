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

public protocol WallpaperDataSource<LocationType>: Sendable {
    associatedtype LocationType: Sendable
    func resolve(_ location: LocationType) async throws -> String
}

// MARK: - Local

public enum LocalWallpaperDataSourceKey: TestDependencyKey {
    public static let testValue: any WallpaperDataSource<LocalWallpaper> = NoopWallpaperDataSource()
}

extension DependencyValues {
    public var localWallpaperDataSource: any WallpaperDataSource<LocalWallpaper> {
        get { self[LocalWallpaperDataSourceKey.self] }
        set { self[LocalWallpaperDataSourceKey.self] = newValue }
    }
}

// MARK: - Remote

public enum RemoteWallpaperDataSourceKey: TestDependencyKey {
    public static let testValue: any WallpaperDataSource<RemoteWallpaper> = NoopWallpaperDataSource()
}

extension DependencyValues {
    public var remoteWallpaperDataSource: any WallpaperDataSource<RemoteWallpaper> {
        get { self[RemoteWallpaperDataSourceKey.self] }
        set { self[RemoteWallpaperDataSourceKey.self] = newValue }
    }
}

// MARK: - YouTube

public enum YouTubeWallpaperDataSourceKey: TestDependencyKey {
    public static let testValue: any WallpaperDataSource<YouTubeWallpaper> = NoopWallpaperDataSource()
}

extension DependencyValues {
    public var youtubeWallpaperDataSource: any WallpaperDataSource<YouTubeWallpaper> {
        get { self[YouTubeWallpaperDataSourceKey.self] }
        set { self[YouTubeWallpaperDataSourceKey.self] = newValue }
    }
}

// MARK: - Noop

private struct NoopWallpaperDataSource<L: Sendable>: WallpaperDataSource {
    func resolve(_ location: L) async throws -> String { "" }
}