import Dependencies
import Domain
import LyricsResolutionLog

extension LyricsResolutionLogKey: DependencyKey {
    public static let liveValue: any Domain.LyricsResolutionLog = FileLyricsResolutionLog()
}
