import Dependencies

public protocol MetadataNormalizer: Sendable {
    func resolve(track: Track) async -> [Track]
}

public enum MetadataNormalizerKey: TestDependencyKey {
    public static let testValue: [any MetadataNormalizer] = []
}

extension DependencyValues {
    public var metadataNormalizers: [any MetadataNormalizer] {
        get { self[MetadataNormalizerKey.self] }
        set { self[MetadataNormalizerKey.self] = newValue }
    }
}
