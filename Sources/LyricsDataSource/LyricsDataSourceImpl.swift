import Alamofire
import Domain
import Foundation

public struct LyricsDataSourceImpl {
    private let requestPerformer: @Sendable (URLRequest) async throws -> Data

    public init() {
        self.init { request in
            try await AF.request(request)
                .validate(statusCode: 200..<300)
                .serializingData()
                .value
        }
    }

    init(
        requestPerformer: @escaping @Sendable (URLRequest) async throws -> Data
    ) {
        self.requestPerformer = requestPerformer
    }
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
        do {
            let request = try api.asURLRequest()
            let data = try await requestPerformer(request)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
