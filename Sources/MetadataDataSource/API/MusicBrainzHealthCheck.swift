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