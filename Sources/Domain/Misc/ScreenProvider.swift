import Dependencies

public protocol ScreenProvider: Sendable {
    var screens: [ScreenInfo] { get }
    var mainScreen: ScreenInfo? { get }
    func windowOccupancy(for screen: ScreenInfo) -> Double
    /// How much of `screen`'s `visibleFrame` is covered by the union of on-screen
    /// windows (0…1). Unlike `windowOccupancy`, overlapping windows are not
    /// double-counted — used to decide whether rendering should pause because the
    /// screen is occluded (#355).
    func windowCoverage(for screen: ScreenInfo) -> Double
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
    func windowCoverage(for screen: ScreenInfo) -> Double { 0 }
}
