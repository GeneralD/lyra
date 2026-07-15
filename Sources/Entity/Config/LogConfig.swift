import Foundation

public struct LogConfig {
    /// Gate for the lyrics-resolution decision trace (#331). Off by default — the
    /// trace records raw metadata, generated candidates, and every tier/validator
    /// accept/reject with its reason, so an intermittent miss can be diagnosed from
    /// the log instead of guessed at.
    public let lyricsResolution: Bool
    /// Optional absolute (or `~`-relative) path override. `nil` derives
    /// `${XDG_CACHE_HOME:-~/.cache}/lyra/lyrics-debug.log`.
    public let file: String?

    public init(lyricsResolution: Bool = false, file: String? = nil) {
        self.lyricsResolution = lyricsResolution
        self.file = file
    }
}

extension LogConfig: Sendable {}
extension LogConfig: Equatable {}

extension LogConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case lyricsResolution = "lyrics_resolution"
        case file
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lyricsResolution = try c.decodeIfPresent(Bool.self, forKey: .lyricsResolution) ?? false
        // Normalize at the boundary: a blank path is treated as "unset" so consumers
        // never receive an empty string to fall over on.
        file = (try c.decodeIfPresent(String.self, forKey: .file))
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lyricsResolution, forKey: .lyricsResolution)
        try c.encodeIfPresent(file, forKey: .file)
    }
}
