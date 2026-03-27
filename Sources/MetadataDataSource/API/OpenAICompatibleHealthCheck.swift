// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
            let (_, response) = try await URLSession.shared.data(for: request)
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