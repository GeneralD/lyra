import Dependencies
import Domain
import RandomSource

extension RandomSourceKey: DependencyKey {
    public static let liveValue: any Domain.RandomSource = SystemRandomSource()
}
