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
