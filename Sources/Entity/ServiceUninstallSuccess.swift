public enum ServiceUninstallSuccess: Sendable, Equatable {
    case uninstalled
    /// lyra's own registration was removed, but `brew services` still registers lyra (#382).
    case uninstalledKeepingHomebrew
}
