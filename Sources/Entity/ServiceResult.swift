public enum ServiceInstallResult: Sendable {
    case installed(path: String)
    case managedByHomebrew
    case bootstrapFailed(status: Int32)
    case failed(detail: String)

    public var message: String {
        switch self {
        case .installed(let path): "Installed and started: \(path)"
        case .managedByHomebrew: "Already managed by brew services. Run 'brew services stop lyra' first."
        case .bootstrapFailed(let status): "Bootstrap failed (status \(status))"
        case .failed(let detail): "Install failed: \(detail)"
        }
    }

    public var succeeded: Bool {
        guard case .installed = self else { return false }
        return true
    }
}

public enum ServiceUninstallResult: Sendable, Equatable {
    case uninstalled
    case managedByHomebrew
    case notInstalled
    case failed(detail: String)

    public var message: String {
        switch self {
        case .uninstalled: "Uninstalled"
        case .managedByHomebrew: "Managed by brew services. Run 'brew services stop lyra' instead."
        case .notInstalled: "Not installed"
        case .failed(let detail): "Uninstall failed: \(detail)"
        }
    }

    public var succeeded: Bool { self == .uninstalled }
}
