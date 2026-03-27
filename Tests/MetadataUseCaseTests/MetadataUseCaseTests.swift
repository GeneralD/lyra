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

@testable import MetadataUseCase

@Suite("MetadataUseCase")
struct MetadataUseCaseTests {
    @Test("resolve returns first candidate when repository returns multiple")
    func resolveReturnsFirst() async {
        let candidates = [
            Track(title: "First", artist: "A"),
            Track(title: "Second", artist: "B"),
        ]
        await withDependencies {
            $0.metadataRepository = MockMetadataRepository(candidates: candidates)
        } operation: {
            let useCase = MetadataUseCaseImpl()
            let result = await useCase.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == candidates.first)
        }
    }

    @Test("resolve returns nil when repository returns empty")
    func resolveReturnsNil() async {
        await withDependencies {
            $0.metadataRepository = MockMetadataRepository(candidates: [])
        } operation: {
            let useCase = MetadataUseCaseImpl()
            let result = await useCase.resolve(track: Track(title: "raw", artist: "raw"))
            #expect(result == nil)
        }
    }

    @Test("resolveCandidates returns all candidates")
    func resolveCandidatesReturnsAll() async {
        let candidates = [
            Track(title: "A", artist: "X"),
            Track(title: "B", artist: "Y"),
            Track(title: "C", artist: "Z"),
        ]
        await withDependencies {
            $0.metadataRepository = MockMetadataRepository(candidates: candidates)
        } operation: {
            let useCase = MetadataUseCaseImpl()
            let result = await useCase.resolveCandidates(track: Track(title: "raw", artist: "raw"))
            #expect(result == candidates)
        }
    }

    @Test("resolveCandidates returns empty when repository returns empty")
    func resolveCandidatesReturnsEmpty() async {
        await withDependencies {
            $0.metadataRepository = MockMetadataRepository(candidates: [])
        } operation: {
            let useCase = MetadataUseCaseImpl()
            let result = await useCase.resolveCandidates(track: Track(title: "raw", artist: "raw"))
            #expect(result.isEmpty)
        }
    }

    @Test("resolve result equals resolveCandidates first element")
    func resolveEqualsResolveCandidatesFirst() async {
        let candidates = [
            Track(title: "Alpha", artist: "One"),
            Track(title: "Beta", artist: "Two"),
        ]
        await withDependencies {
            $0.metadataRepository = MockMetadataRepository(candidates: candidates)
        } operation: {
            let useCase = MetadataUseCaseImpl()
            let input = Track(title: "raw", artist: "raw")
            let resolved = await useCase.resolve(track: input)
            let allCandidates = await useCase.resolveCandidates(track: input)
            #expect(resolved == allCandidates.first)
        }
    }
}

// MARK: - Mocks

private struct MockMetadataRepository: MetadataRepository {
    let candidates: [Track]
    func resolve(track: Track) async -> [Track] { candidates }
}