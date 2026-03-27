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

public struct MetadataUseCaseImpl {
    @Dependency(\.metadataRepository) private var repository

    public init() {}
}

extension MetadataUseCaseImpl: MetadataUseCase {
    public func resolve(track: Track) async -> Track? {
        let candidates = await repository.resolve(track: track)
        return candidates.first
    }

    public func resolveCandidates(track: Track) async -> [Track] {
        await repository.resolve(track: track)
    }
}