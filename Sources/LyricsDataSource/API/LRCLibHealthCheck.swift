import Domain
import Foundation
@preconcurrency import Papyrus

public struct LRCLibHealthCheck: Sendable {
    private let healthCheckRunner: @Sendable () async throws -> Void

    public init() {
        let api = LRCLibAPI(provider: Provider(baseURL: LRCLibAPI.baseURL))
        self.init {
            _ = try await api.healthCheck()
        }
    }

    init(
        healthCheckRunner: @escaping @Sendable () async throws -> Void
    ) {
        self.healthCheckRunner = healthCheckRunner
    }
}

extension LRCLibHealthCheck: HealthCheckable {
    public var serviceName: String { "LRCLIB API" }

    public func healthCheck() async -> HealthCheckResult {
        let start = ContinuousClock.now
        do {
            try await healthCheckRunner()
            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            return HealthCheckResult(status: .pass, detail: "reachable (\(ms)ms)", latency: Double(ms) / 1000)
        } catch let error as PapyrusError {
            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            if let code = error.response?.statusCode ?? (error.response != nil ? -1 : nil) {
                return HealthCheckResult(status: .fail, detail: "HTTP \(code)", latency: Double(ms) / 1000)
            }
            return HealthCheckResult(status: .fail, detail: error.message)
        } catch {
            return HealthCheckResult(status: .fail, detail: error.localizedDescription)
        }
    }
}
