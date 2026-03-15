import BackdropDomain
import Dependencies
import Foundation

public struct LyricsService {
    @Dependency(\.lyricsRepository) private var remote
    @Dependency(\.lyricsCache) private var cache

    public init() {}

    public func fetch(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult {
        guard !artist.isEmpty else {
            return await remote.fetch(title: title, artist: artist, duration: duration) ?? .empty
        }
        if let cached = await cache.read(title: title, artist: artist) { return cached }
        guard let result = await remote.fetch(title: title, artist: artist, duration: duration) else {
            return .empty
        }
        try? await cache.write(title: title, artist: artist, result: result)
        return result
    }
}

extension LyricsService: Sendable {}
