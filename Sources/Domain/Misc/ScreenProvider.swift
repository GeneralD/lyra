import Dependencies

public protocol ScreenProvider: Sendable {
    var screens: [ScreenInfo] { get }
    var mainScreen: ScreenInfo? { get }
    func windowOccupancy(for screen: ScreenInfo) -> Double
}

public enum ScreenProviderKey: TestDependencyKey {
    public static let testValue: any ScreenProvider = UnimplementedScreenProvider()
}

extension DependencyValues {
    public var screenProvider: any ScreenProvider {
        get { self[ScreenProviderKey.self] }
        set { self[ScreenProviderKey.self] = newValue }
    }
}

private struct UnimplementedScreenProvider: ScreenProvider {
    var screens: [ScreenInfo] { [] }
    var mainScreen: ScreenInfo? { nil }
    func windowOccupancy(for screen: ScreenInfo) -> Double { 0 }
}
