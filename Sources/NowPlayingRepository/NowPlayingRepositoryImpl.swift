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

public struct NowPlayingRepositoryImpl: Sendable {
    @Dependency(\.mediaRemoteDataSource) private var dataSource

    public init() {}
}

extension NowPlayingRepositoryImpl: NowPlayingRepository {
    public func stream() -> AsyncStream<NowPlaying?> {
        let dataSource = self.dataSource
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    switch await dataSource.poll() {
                    case .info(let nowPlaying):
                        continuation.yield(nowPlaying)
                    case .noInfo:
                        continuation.yield(nil)
                    case .eof:
                        continuation.finish()
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}