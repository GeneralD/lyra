import Domain
import Foundation

extension MusicBrainzAPI: HealthCheckable {
    public var serviceName: String { "MusicBrainz API" }

    public func healthCheck() async -> HealthCheckResult {
        guard let url = URL(string: Self.baseURL + "/recording?query=test&fmt=json&limit=1") else {
            return HealthCheckResult(status: .fail, detail: "invalid URL")
        }
        var request = URLRequest(url: url)
        request.setValue("lyra (https://github.com/GeneralD/lyra)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let start = ContinuousClock.now
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
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
