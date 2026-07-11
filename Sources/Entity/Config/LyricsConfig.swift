public struct LyricsConfig {
    public let fallbackCommand: [String]
    public let timeoutMs: FlexibleDouble

    public init(fallbackCommand: [String] = [], timeoutMs: FlexibleDouble = 5000) {
        self.fallbackCommand = fallbackCommand
        self.timeoutMs = timeoutMs
    }
}

extension LyricsConfig: Sendable {}
extension LyricsConfig: Equatable {}

extension LyricsConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case fallbackCommand = "fallback_command"
        case timeoutMs = "timeout_ms"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fallbackCommand = try c.decodeIfPresent([String].self, forKey: .fallbackCommand) ?? []
        timeoutMs = try c.decodeIfPresent(FlexibleDouble.self, forKey: .timeoutMs) ?? 5000
    }
}
