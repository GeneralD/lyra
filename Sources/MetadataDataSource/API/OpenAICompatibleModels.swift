public struct ChatCompletionResponse: Decodable, Sendable {
    public let choices: [Choice]

    public struct Choice: Decodable, Sendable {
        public let message: Message
    }

    public struct Message: Decodable, Sendable {
        public let content: String
    }
}

public struct ExtractedMetadata: Decodable, Sendable {
    public let title: String
    public let artist: String
}
