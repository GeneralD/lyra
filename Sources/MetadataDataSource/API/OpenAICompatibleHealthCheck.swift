import Domain
import Foundation

extension OpenAICompatibleAPI: HealthCheckable {
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

        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

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
