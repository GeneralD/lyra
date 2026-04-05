import Dependencies
import Domain
import ProcessHandler
import VersionHandler

extension ProcessHandlerKey: DependencyKey {
    public static let liveValue: any ProcessHandler = ProcessHandlerImpl(
        lock: ProcessLockKey.liveValue,
        processManager: ProcessManagingKey.liveValue
    )
}

extension ProcessLockKey: DependencyKey {
    public static let liveValue: any ProcessLockable = ProcessLock.shared
}

extension ProcessManagingKey: DependencyKey {
    public static let liveValue: any ProcessManaging = ProcessManager()
}

extension VersionHandlerKey: DependencyKey {
    public static let liveValue: any VersionHandler = VersionHandlerImpl()
}
