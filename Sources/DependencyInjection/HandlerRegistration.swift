import BenchmarkHandler
import ConfigHandler
import Dependencies
import Domain
import HealthHandler
import ProcessHandler
import ServiceHandler
import TrackHandler
import VersionHandler

extension ProcessHandlerKey: DependencyKey {
    public static let liveValue: any ProcessHandler = ProcessHandlerImpl()
}

extension VersionHandlerKey: DependencyKey {
    public static let liveValue: any VersionHandler = VersionHandlerImpl()
}

extension ServiceHandlerKey: DependencyKey {
    public static let liveValue: any ServiceHandler = ServiceHandlerImpl()
}

extension HealthHandlerKey: DependencyKey {
    public static let liveValue: any HealthHandler = HealthHandlerImpl()
}

extension TrackHandlerKey: DependencyKey {
    public static let liveValue: any TrackHandler = TrackHandlerImpl()
}

extension ConfigHandlerKey: DependencyKey {
    public static let liveValue: any ConfigHandler = ConfigHandlerImpl()
}

extension BenchmarkHandlerKey: DependencyKey {
    public static let liveValue: any BenchmarkHandler = BenchmarkHandlerImpl()
}
