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
}

public enum ServiceUninstallFailure: Error, Sendable, Equatable {
    case managedByHomebrew
    case notInstalled
    case failed(detail: String)
}
