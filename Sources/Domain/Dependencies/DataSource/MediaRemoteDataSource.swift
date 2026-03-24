import Dependencies

public protocol MediaRemoteDataSource: Sendable {
    func poll() async -> MediaRemotePollResult
}

public enum MediaRemoteDataSourceKey: TestDependencyKey {
    public static let testValue: any MediaRemoteDataSource = UnimplementedMediaRemoteDataSource()
}

extension DependencyValues {
    public var mediaRemoteDataSource: any MediaRemoteDataSource {
        get { self[MediaRemoteDataSourceKey.self] }
        set { self[MediaRemoteDataSourceKey.self] = newValue }
    }
}

private struct UnimplementedMediaRemoteDataSource: MediaRemoteDataSource {
    func poll() async -> MediaRemotePollResult { .eof }
}
