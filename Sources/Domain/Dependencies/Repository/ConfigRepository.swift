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

public protocol ConfigRepository: Sendable {
    func loadAppStyle() -> AppStyle
    func validate() -> ConfigValidationResult
    func template(format: ConfigFormat) -> String?
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String
}

public enum ConfigRepositoryKey: TestDependencyKey {
    public static let testValue: any ConfigRepository = UnimplementedConfigRepository()
}

extension DependencyValues {
    public var configRepository: any ConfigRepository {
        get { self[ConfigRepositoryKey.self] }
        set { self[ConfigRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedConfigRepository: ConfigRepository {
    func loadAppStyle() -> AppStyle { .init() }
    func validate() -> ConfigValidationResult { .defaults }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
}