public struct AIEndpoint: Sendable {
    public let endpoint: String
    public let model: String
    public let apiKey: String

    public init(endpoint: String, model: String, apiKey: String) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
    }
}
