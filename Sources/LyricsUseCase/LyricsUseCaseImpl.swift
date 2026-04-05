import Dependencies
import Domain
import Foundation

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

    public func parseLyricsContent(from result: LyricsResult?) -> LyricsContent? {
        guard let result else { return nil }
        if let synced = result.syncedLyrics.flatMap(Self.parseSyncedLyrics), !synced.isEmpty {
            return .timed(synced)
        }
        guard let plain = result.plainLyrics else { return nil }
        return .plain(plain.components(separatedBy: "\n"))
    }
}

extension LyricsUseCaseImpl {
    private static func parseSyncedLyrics(_ raw: String) -> [LyricLine] {
        let re = #/\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)/#
        return raw.split(separator: "\n").compactMap { line in
            guard let match = try? re.firstMatch(in: line),
                let min = Double(String(match.1)),
                let sec = Double(String(match.2))
            else { return nil }
            return LyricLine(
                time: min * 60 + sec,
                text: String(match.3).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
