import Dependencies

public protocol ServiceHandler: Sendable {
    /// Whether `install()` can proceed, answered without side effects. Callers check it before
    /// stopping a running daemon: under `brew services` the KeepAlive job relaunches whatever
    /// they stop, so the install must be refused first (#380).
    var installReadiness: ServiceInstallReadinessResult { get }
    func install() -> ServiceInstallResult
    /// Removes only lyra's own registration. Returns `.uninstalledKeepingHomebrew` when
    /// `brew services` also registers lyra; callers must not stop the daemon then, because the
    /// brew job's KeepAlive relaunches whatever they stop (#382).
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
