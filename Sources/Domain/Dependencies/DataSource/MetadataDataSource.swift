import Dependencies

public protocol MetadataDataSource: Sendable {
    func resolve(track: Track) async -> [Track]
}

public enum MetadataDataSourceKey: TestDependencyKey {
    public static let testValue: [any MetadataDataSource] = []
}

extension DependencyValues {
    public var metadataDataSources: [any MetadataDataSource] {
        get { self[MetadataDataSourceKey.self] }
        set { self[MetadataDataSourceKey.self] = newValue }
    }
}
