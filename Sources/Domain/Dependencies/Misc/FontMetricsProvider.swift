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

import Dependencies
import Foundation

public protocol FontMetricsProvider: Sendable {
    @MainActor func lineHeight(fontName: String, fontSize: Double, spacing: Double) -> Double
}

public enum FontMetricsProviderKey: TestDependencyKey {
    public static let testValue: any FontMetricsProvider = StubFontMetrics()
}

extension DependencyValues {
    public var fontMetrics: any FontMetricsProvider {
        get { self[FontMetricsProviderKey.self] }
        set { self[FontMetricsProviderKey.self] = newValue }
    }
}

private struct StubFontMetrics: FontMetricsProvider {
    @MainActor func lineHeight(fontName: String, fontSize: Double, spacing: Double) -> Double {
        fontSize + spacing * 2
    }
}