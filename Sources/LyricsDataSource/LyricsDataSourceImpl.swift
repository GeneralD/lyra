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

import Alamofire
import Domain
import Foundation

public struct LyricsDataSourceImpl {
    public init() {}
}

extension LyricsDataSourceImpl: LyricsDataSource {
    public func get(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        let result = await lrclib(LyricsResult.self, from: .get(title: title, artist: artist, duration: duration))
        guard let result, result.plainLyrics != nil || result.syncedLyrics != nil else { return nil }
        return result
    }

    public func search(query: String) async -> [LyricsResult]? {
        await lrclib([LyricsResult].self, from: .search(query: query))
    }
}

extension LyricsDataSourceImpl {
    fileprivate func lrclib<T: Decodable & Sendable>(_ type: T.Type, from api: LRCLibAPI) async -> T? {
        await AF.request(api)
            .validate(statusCode: 200..<300)
            .serializingDecodable(type)
            .response.value
    }
}