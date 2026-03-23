import Alamofire
import Domain
import Dependencies
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

extension LyricsDataSourceKey: DependencyKey {
    public static let liveValue: any LyricsDataSource = LyricsDataSourceImpl()
}

private extension LyricsDataSourceImpl {
    func lrclib<T: Decodable & Sendable>(_ type: T.Type, from api: LRCLibAPI) async -> T? {
        await AF.request(api)
            .validate(statusCode: 200 ..< 300)
            .serializingDecodable(type)
            .response.value
    }
}
