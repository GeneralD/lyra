import Domain
import Dependencies

public struct LyricsUseCaseImpl {
    @Dependency(\.lyricsRepository) private var repository

    public init() {}
}

extension LyricsUseCaseImpl: LyricsUseCase {
    public func fetchLyrics(track: Track) async -> LyricsResult {
        await repository.fetchLyrics(track: track) ?? .empty
    }

    public func fetchLyrics(candidates: [Track]) async -> LyricsResult {
        await repository.fetchLyrics(candidates: candidates) ?? .empty
    }
}

extension LyricsUseCaseKey: DependencyKey {
    public static let liveValue: any LyricsUseCase = LyricsUseCaseImpl()
}
