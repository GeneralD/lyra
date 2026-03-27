public struct AIConfig {
    public let endpoint: String
    public let model: String
    public let apiKey: String
}

extension AIConfig: Sendable {}

extension AIConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case endpoint, model
        case apiKey = "api_key"
    }
}
