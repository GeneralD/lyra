public enum ConfigReloadOutcome {
    case updated(AppStyle)
    case invalid(ConfigReloadFailure)
}

extension ConfigReloadOutcome: Sendable {}
