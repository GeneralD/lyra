import Foundation

/// `[developer]` — diagnostic / debug toggles, off by default. This is deliberately
/// *not* a general logging subsystem (no levels, no rotation): lyra emits operational
/// failures to stderr (#318), and this section is a home for opt-in developer traces.
public struct DeveloperConfig {
    /// Enable the lyrics-resolution decision trace (#331). The trace records raw
    /// metadata, generated candidates, and every tier/validator accept/reject with
    /// its reason, so an intermittent miss can be diagnosed from the log instead of
    /// guessed at.
    public let lyricsResolution: Bool
    /// Optional absolute (or `~`-relative) path for the lyrics-resolution trace.
    /// `nil` derives `${XDG_CACHE_HOME:-~/.cache}/lyra/lyrics-debug.log`.
    public let lyricsResolutionFile: String?

    public init(lyricsResolution: Bool = false, lyricsResolutionFile: String? = nil) {
        self.lyricsResolution = lyricsResolution
        self.lyricsResolutionFile = lyricsResolutionFile
    }
}

extension DeveloperConfig: Sendable {}
extension DeveloperConfig: Equatable {}

extension DeveloperConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case lyricsResolution = "lyrics_resolution"
        case lyricsResolutionFile = "lyrics_resolution_file"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lyricsResolution = try c.decodeIfPresent(Bool.self, forKey: .lyricsResolution) ?? false
        // Normalize at the boundary: a blank path is treated as "unset" so consumers
        // never receive an empty string to fall over on.
        lyricsResolutionFile = (try c.decodeIfPresent(String.self, forKey: .lyricsResolutionFile))
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lyricsResolution, forKey: .lyricsResolution)
        try c.encodeIfPresent(lyricsResolutionFile, forKey: .lyricsResolutionFile)
    }
}
