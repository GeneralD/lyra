public enum ServiceUninstallFailure: Error, Sendable, Equatable {
    case managedByHomebrew
    case notInstalled
    case failed(detail: String)
}
