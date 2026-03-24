public struct AIConfig: Sendable, Codable {
    public let endpoint: String
    public let model: String
    public let apiKey: String

    enum CodingKeys: String, CodingKey {
        case endpoint, model
        case apiKey = "api_key"
    }
}
