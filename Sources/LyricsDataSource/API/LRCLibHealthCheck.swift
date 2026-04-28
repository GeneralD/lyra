import Domain
import Foundation

public struct LRCLibHealthCheck: Sendable {
    private let requestPerformer: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init() {
        self.init(requestPerformer: Self.defaultRequestPerformer)
    }

    init(
        requestPerformer: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.requestPerformer = requestPerformer
    }

    /// Default backend used by `init()`. Exposed `internal` so coverage tests
    /// can invoke it directly without going through the network-bound init.
    static let defaultRequestPerformer: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        try await URLSession.shared.data(for: request)
    }
}

extension LRCLibHealthCheck: HealthCheckable {
    public var serviceName: String { "LRCLIB API" }

    public func healthCheck() async -> HealthCheckResult {
        // baseURL + literal path is a known-valid URL string; cannot fail.
        let url = URL(string: "\(LRCLibAPI.baseURL)/api/search?q=test")!
        var request = URLRequest(url: url)
        request.setValue(LRCLibAPI.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let start = ContinuousClock.now
        do {
            let (_, response) = try await requestPerformer(request)
            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            guard let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return HealthCheckResult(status: .fail, detail: "HTTP \(code)", latency: Double(ms) / 1000)
            }
            return HealthCheckResult(status: .pass, detail: "reachable (\(ms)ms)", latency: Double(ms) / 1000)
        } catch {
            return HealthCheckResult(status: .fail, detail: error.localizedDescription)
        }
    }
}
