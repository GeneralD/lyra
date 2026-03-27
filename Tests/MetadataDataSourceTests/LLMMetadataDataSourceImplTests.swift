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
import Domain
import Foundation
import Testing

@testable import MetadataDataSource

struct LLMMetadataDataSourceImplTests {
    @Test("Returns empty when AI is not configured")
    func unconfiguredReturnsEmpty() async {
        let dataSource = withDependencies {
            $0.configDataSource = StubConfigDataSource(loadResult: nil)
        } operation: {
            LLMMetadataDataSourceImpl()
        }

        let result = await dataSource.resolve(track: Track(title: "Some Song", artist: "Some Artist"))
        #expect(result.isEmpty)
    }
}

private struct StubConfigDataSource: ConfigDataSource {
    var loadResult: ConfigLoadResult?
    func load() -> ConfigLoadResult? { loadResult }
    func tryDecode() throws -> String { "" }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    func existingConfigPath() -> String? { nil }
}