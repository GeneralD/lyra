import Dependencies
import Domain
import ProcessExecutor

extension ProcessExecutorKey: DependencyKey {
    public static let liveValue: any ProcessExecutor = ProcessExecutorImpl()
}
