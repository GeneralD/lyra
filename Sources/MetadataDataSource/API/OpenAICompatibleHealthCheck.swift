import Domain
import Foundation

public struct OpenAICompatibleHealthCheck: Sendable {
    private let config: AIEndpoint
    private let requestPerformer: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(config: AIEndpoint) {
        self.init(config: config, requestPerformer: Self.defaultRequestPerformer)
    }

    init(
        config: AIEndpoint,
        requestPerformer: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.config = config
        self.requestPerformer = requestPerformer
    }

    /// Default backend used by `init(config:)`. Exposed `internal` so coverage
    /// tests can invoke it directly without going through the network-bound init.
    static let defaultRequestPerformer: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        try await URLSession.shared.data(for: request)
    }

    private var normalizedEndpoint: String {
        config.endpoint.hasSuffix("/")
            ? String(config.endpoint.dropLast())
            : config.endpoint
    }
}

private struct PingRequest: Encodable, Sendable {
    let model: String
    let messages: [Message]
    let maxTokens: Int

    init(model: String) {
        self.model = model
        self.messages = [Message(role: "user", content: "ping")]
        self.maxTokens = 1
    }

    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model, messages
        case maxTokens = "max_tokens"
    }
}

extension OpenAICompatibleHealthCheck: HealthCheckable {
    public var serviceName: String { "AI endpoint" }

    public func healthCheck() async -> HealthCheckResult {
        guard let url = URL(string: normalizedEndpoint + "/chat/completions") else {
            return HealthCheckResult(status: .fail, detail: "invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        // Encoding a fixed-shape Encodable struct of String/Int fields cannot fail.
        request.httpBody = try! JSONEncoder().encode(PingRequest(model: config.model))

        let start = ContinuousClock.now
        do {
            let (_, response) = try await requestPerformer(request)
            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            guard let http = response as? HTTPURLResponse else {
                return HealthCheckResult(status: .fail, detail: "no HTTP response", latency: Double(ms) / 1000)
            }
            switch http.statusCode {
            case 200..<300:
                return HealthCheckResult(status: .pass, detail: "authenticated (\(ms)ms)", latency: Double(ms) / 1000)
            case 401, 403:
                return HealthCheckResult(status: .fail, detail: "HTTP \(http.statusCode) — check api_key in [ai]", latency: Double(ms) / 1000)
            default:
                return HealthCheckResult(status: .fail, detail: "HTTP \(http.statusCode)", latency: Double(ms) / 1000)
            }
        } catch {
            return HealthCheckResult(status: .fail, detail: error.localizedDescription)
        }
    }
}
