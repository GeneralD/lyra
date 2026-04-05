import Dependencies

public protocol VersionHandler: Sendable {
    var version: String { get }
}

public enum VersionHandlerKey: TestDependencyKey {
    public static let testValue: any VersionHandler = UnimplementedVersionHandler()
}

extension DependencyValues {
    public var versionHandler: any VersionHandler {
        get { self[VersionHandlerKey.self] }
        set { self[VersionHandlerKey.self] = newValue }
    }
}

private struct UnimplementedVersionHandler: VersionHandler {
    var version: String { fatalError("VersionHandler.version not implemented") }
}
