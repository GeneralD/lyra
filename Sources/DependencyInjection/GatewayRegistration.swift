import CoreAudioTapGateway
import DarwinGateway
import Dependencies
import Domain

extension ProcessGatewayKey: DependencyKey {
    public static let liveValue: any ProcessGateway = DarwinGateway()
}

extension AudioTapGatewayKey: DependencyKey {
    public static let liveValue: any AudioTapGateway = CoreAudioTapGateway()
}
