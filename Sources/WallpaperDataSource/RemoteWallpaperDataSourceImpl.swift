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

import Domain
import Foundation

public struct RemoteWallpaperDataSourceImpl: Sendable {
    public init() {}
}

extension RemoteWallpaperDataSourceImpl: WallpaperDataSource {
    /// Downloads to a temp file in the cache folder. Returns the temp file path.
    /// Cache deduplication is handled by WallpaperRepository.
    public func resolve(_ location: RemoteWallpaper) async throws -> String {
        let cache = try WallpaperCache()
        let tempPath = cache.tempPath(for: location.url)

        let (tempURL, response) = try await URLSession.shared.download(from: location.url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: tempURL)
            throw URLError(.badServerResponse)
        }

        let destURL = URL(fileURLWithPath: tempPath)
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        return tempPath
    }
}