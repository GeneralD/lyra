import Dependencies

public protocol ResourceSampler: Sendable {
    var current: ResourceSnapshot { get }
}

public enum ResourceSamplerKey: TestDependencyKey {
    public static let testValue: any ResourceSampler = UnimplementedResourceSampler()
}

extension DependencyValues {
    public var resourceSampler: any ResourceSampler {
        get { self[ResourceSamplerKey.self] }
        set { self[ResourceSamplerKey.self] = newValue }
    }
}

private struct UnimplementedResourceSampler: ResourceSampler {
    var current: ResourceSnapshot { fatalError("ResourceSampler.current not implemented") }
}
