public enum ServiceInstallFailure: Error, Sendable, Equatable {
    case managedByHomebrew
    case bootstrapFailed(status: Int32)
    case failed(detail: String)
}
