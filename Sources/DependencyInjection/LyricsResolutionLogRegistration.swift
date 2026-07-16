import Dependencies
import DeveloperLog
import Domain

extension LyricsResolutionLogKey: DependencyKey {
    /// The lyrics-resolution trace instance: a general `FileDeveloperLog` wired to the
    /// `[developer] lyrics_resolution` toggle and the `lyrics-debug.log` file. Reading
    /// config here (not in the sink) keeps `FileDeveloperLog` purpose-agnostic so a
    /// future trace reuses it with its own toggle and filename.
    public static let liveValue: any Domain.DeveloperLog = {
        @Dependency(\.configDataSource) var configDataSource
        let developer = configDataSource.load()?.config.developer
        return FileDeveloperLog(
            enabled: developer?.lyricsResolution ?? false,
            path: FileDeveloperLog.resolvedPath(
                configured: developer?.lyricsResolutionFile, defaultFilename: "lyrics-debug.log"))
    }()
}
