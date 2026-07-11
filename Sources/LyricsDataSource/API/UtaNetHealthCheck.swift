import Domain
import Foundation

public struct UtaNetHealthCheck: Sendable {
    private let healthCheckRunner: @Sendable () async throws -> Void

    public init() {
        self.init {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: configuration)
            guard let url = URL(string: UtaNetAPI.baseURL) else { throw UtaNetError.invalidURL }
            var request = URLRequest(url: url)
            request.setValue(UtaNetAPI.userAgent, forHTTPHeaderField: "User-Agent")
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw UtaNetError.httpStatus(http.statusCode)
            }
        }
    }

    init(
        healthCheckRunner: @escaping @Sendable () async throws -> Void
    ) {
        self.healthCheckRunner = healthCheckRunner
    }
}

extension UtaNetHealthCheck: HealthCheckable {
    public var serviceName: String { "uta-net" }

    public func healthCheck() async -> HealthCheckResult {
        let start = ContinuousClock.now

        func elapsedMs() -> Int64 {
            let elapsed = ContinuousClock.now - start
            return elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
        }

        do {
            try await healthCheckRunner()
            let ms = elapsedMs()
            return HealthCheckResult(status: .pass, detail: "reachable (\(ms)ms)", latency: Double(ms) / 1000)
        } catch let error as UtaNetError {
            let ms = elapsedMs()
            return HealthCheckResult(status: .fail, detail: error.errorDescription ?? "\(error)", latency: Double(ms) / 1000)
        } catch {
            return HealthCheckResult(status: .fail, detail: error.localizedDescription)
        }
    }
}
