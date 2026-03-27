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

import ConfigDataSource
import Dependencies
import Domain
import LyricsDataSource
import MediaRemoteDataSource
import MetadataDataSource
import WallpaperDataSource

extension ConfigDataSourceKey: DependencyKey {
    public static let liveValue: any ConfigDataSource = ConfigDataSourceImpl()
}

extension LyricsDataSourceKey: DependencyKey {
    public static let liveValue: any LyricsDataSource = LyricsDataSourceImpl()
}

extension MediaRemoteDataSourceKey: DependencyKey {
    public static let liveValue: any MediaRemoteDataSource = MediaRemoteBridge()
}

extension LLMMetadataDataSourceKey: DependencyKey {
    public static let liveValue: any MetadataDataSource<Track> = LLMMetadataDataSourceImpl()
}

extension MusicBrainzMetadataDataSourceKey: DependencyKey {
    public static let liveValue: any MetadataDataSource<MusicBrainzMetadata> = MusicBrainzMetadataDataSourceImpl()
}

extension RegexMetadataDataSourceKey: DependencyKey {
    public static let liveValue: any MetadataDataSource<Track> = RegexMetadataDataSourceImpl()
}

extension LocalWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<LocalWallpaper> = LocalWallpaperDataSourceImpl()
}

extension RemoteWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<RemoteWallpaper> = RemoteWallpaperDataSourceImpl()
}

extension YouTubeWallpaperDataSourceKey: DependencyKey {
    public static let liveValue: any WallpaperDataSource<YouTubeWallpaper> = YouTubeWallpaperDataSourceImpl()
}