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

public protocol MetadataRepository: Sendable {
    func resolve(track: Track) async -> [Track]
}

public enum MetadataRepositoryKey: TestDependencyKey {
    public static let testValue: any MetadataRepository = UnimplementedMetadataRepository()
}

extension DependencyValues {
    public var metadataRepository: any MetadataRepository {
        get { self[MetadataRepositoryKey.self] }
        set { self[MetadataRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedMetadataRepository: MetadataRepository {
    func resolve(track: Track) async -> [Track] { [] }
}