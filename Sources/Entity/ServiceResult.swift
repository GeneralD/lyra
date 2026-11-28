public typealias ServiceInstallResult = Result<ServiceInstallSuccess, ServiceInstallFailure>
public typealias ServiceInstallReadinessResult = Result<ServiceInstallReady, ServiceInstallFailure>
public typealias ServiceUninstallResult = Result<ServiceUninstallSuccess, ServiceUninstallFailure>

public enum ServiceInstallSuccess: Sendable, Equatable {
    case installed(path: String)
}

public enum ServiceInstallReady: Sendable, Equatable {
    case ready
}

public enum ServiceInstallFailure: Error, Sendable, Equatable {
    case managedByHomebrew
    case bootstrapFailed(status: Int32)
    case failed(detail: String)
}

public enum ServiceUninstallSuccess: Sendable, Equatable {
    case uninstalled
    /// lyra's own registration was removed, but `brew services` still registers lyra (#382).
    case uninstalledKeepingHomebrew
}

public enum ServiceUninstallFailure: Error, Sendable, Equatable {
    case managedByHomebrew
    case notInstalled
    case failed(detail: String)
}
