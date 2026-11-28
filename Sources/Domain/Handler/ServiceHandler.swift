import Dependencies

public protocol ServiceHandler: Sendable {
    /// Whether `install()` can proceed, answered without side effects. Callers check it before
    /// stopping a running daemon: under `brew services` the KeepAlive job relaunches whatever
    /// they stop, so the install must be refused first (#380).
    var installReadiness: ServiceInstallReadinessResult { get }
    func install() -> ServiceInstallResult
    func uninstall() -> ServiceUninstallResult
}

public enum ServiceHandlerKey: TestDependencyKey {
    public static let testValue: any ServiceHandler = UnimplementedServiceHandler()
}

extension DependencyValues {
    public var serviceHandler: any ServiceHandler {
        get { self[ServiceHandlerKey.self] }
        set { self[ServiceHandlerKey.self] = newValue }
    }
}

private struct UnimplementedServiceHandler: ServiceHandler {
    var installReadiness: ServiceInstallReadinessResult {
        fatalError("ServiceHandler.installReadiness not implemented")
    }
    func install() -> ServiceInstallResult { fatalError("ServiceHandler.install not implemented") }
    func uninstall() -> ServiceUninstallResult { fatalError("ServiceHandler.uninstall not implemented") }
}
