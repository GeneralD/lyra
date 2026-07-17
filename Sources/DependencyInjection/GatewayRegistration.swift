import CoreAudioTapGateway
import DarwinGateway
import Dependencies
import Domain
import FileWatchGateway

extension ProcessGatewayKey: DependencyKey {
    public static let liveValue: any ProcessGateway = DarwinGateway()
}

extension AudioTapGatewayKey: DependencyKey {
    public static let liveValue: any AudioTapGateway = CoreAudioTapGateway()
}

extension ConfigWatchGatewayKey: DependencyKey {
    public static let liveValue: any ConfigWatchGateway = FileWatchGateway()
}
