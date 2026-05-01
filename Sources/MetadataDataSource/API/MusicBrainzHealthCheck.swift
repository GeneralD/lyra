import Domain
import Foundation
@preconcurrency import Papyrus

public struct MusicBrainzHealthCheck: Sendable {
    private let healthCheckRunner: @Sendable () async throws -> Void

    public init() {
        self.init {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: configuration)
            let api = MusicBrainzAPI(provider: Provider(baseURL: MusicBrainzAPI.baseURL, urlSession: session))
            _ = try await api.healthCheck()
        }
    }

    init(
        healthCheckRunner: @escaping @Sendable () async throws -> Void
    ) {
        self.healthCheckRunner = healthCheckRunner
    }
}

extension MusicBrainzHealthCheck: HealthCheckable {
    public var serviceName: String { "MusicBrainz API" }

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
        } catch let error as PapyrusError {
            let ms = elapsedMs()
            if let code = error.response?.statusCode ?? (error.response != nil ? -1 : nil) {
                return HealthCheckResult(status: .fail, detail: "HTTP \(code)", latency: Double(ms) / 1000)
            }
            return HealthCheckResult(status: .fail, detail: error.message, latency: Double(ms) / 1000)
        } catch {
            return HealthCheckResult(status: .fail, detail: error.localizedDescription)
        }
    }
}
