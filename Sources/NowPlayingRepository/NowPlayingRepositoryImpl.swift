import Domain
import Dependencies
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

// MARK: - DependencyKey

extension NowPlayingRepositoryKey: DependencyKey {
    public static let liveValue: any NowPlayingRepository = NowPlayingRepositoryImpl()
}
