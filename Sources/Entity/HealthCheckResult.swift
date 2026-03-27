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

import Foundation

public struct HealthCheckResult {
    public enum Status {
        case pass
        case fail
        case skip
    }

    public let status: Status
    public let detail: String
    public let latency: TimeInterval?

    public init(status: Status, detail: String, latency: TimeInterval? = nil) {
        self.status = status
        self.detail = detail
        self.latency = latency
    }
}

extension HealthCheckResult: Sendable {}
extension HealthCheckResult.Status: Sendable {}