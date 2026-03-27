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
import Testing

@testable import LyricsDataSource

@Suite("LyricsDataSource")
struct LyricsDataSourceTests {

    @Test("LRCLibAPI.get builds correct URL with title, artist, and duration")
    func getEndpointConstruction() throws {
        let api = LRCLibAPI.get(title: "Numb", artist: "Linkin Park", duration: 187)
        let request = try api.asURLRequest()
        let url = request.url!.absoluteString
        #expect(url.contains("lrclib.net/api/get"))
        #expect(url.contains("track_name=Numb"))
        #expect(url.contains("artist_name=Linkin%20Park"))
        #expect(url.contains("duration=187"))
    }

    @Test("LRCLibAPI.get omits duration when nil")
    func getEndpointWithoutDuration() throws {
        let api = LRCLibAPI.get(title: "Song", artist: "Artist", duration: nil)
        let request = try api.asURLRequest()
        let url = request.url!.absoluteString
        #expect(!url.contains("duration"))
    }

    @Test("LRCLibAPI.search builds correct URL with query")
    func searchEndpointConstruction() throws {
        let api = LRCLibAPI.search(query: "hello world")
        let request = try api.asURLRequest()
        let url = request.url!.absoluteString
        #expect(url.contains("lrclib.net/api/search"))
        #expect(url.contains("q=hello%20world"))
    }

    @Test("LRCLibAPI sets User-Agent header")
    func userAgentHeader() throws {
        let api = LRCLibAPI.get(title: "T", artist: "A", duration: nil)
        let request = try api.asURLRequest()
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "lyra (https://github.com/GeneralD/lyra)")
    }

    @Test("LRCLibAPI uses GET method")
    func httpMethod() throws {
        let api = LRCLibAPI.search(query: "test")
        let request = try api.asURLRequest()
        #expect(request.httpMethod == "GET")
    }
}