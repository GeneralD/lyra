import Dependencies
import Foundation

public protocol LyricsUseCase: Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult
    func fetchLyrics(candidates: [Track]) async -> LyricsResult
}

public enum LyricsUseCaseKey: TestDependencyKey {
    public static let testValue: any LyricsUseCase = UnimplementedLyricsUseCase()
}

extension DependencyValues {
    public var lyricsUseCase: any LyricsUseCase {
        get { self[LyricsUseCaseKey.self] }
        set { self[LyricsUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedLyricsUseCase: LyricsUseCase {
    func fetchLyrics(track: Track) async -> LyricsResult { .empty }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult { .empty }
}
