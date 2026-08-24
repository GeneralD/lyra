import Dependencies
import Domain
import ErrorLog

extension ErrorLogKey: DependencyKey {
    public static let liveValue: any Domain.ErrorLog = StandardErrorLog()
}
