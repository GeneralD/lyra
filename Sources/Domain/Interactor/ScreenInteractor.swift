import Dependencies

public protocol ScreenInteractor: Sendable {
    var screenSelector: ScreenSelector { get }
    var screenDebounce: Double { get }
    func resolveLayout() -> ScreenLayout
}

public enum ScreenInteractorKey: TestDependencyKey {
    public static let testValue: any ScreenInteractor = UnimplementedScreenInteractor()
}

extension DependencyValues {
    public var screenInteractor: any ScreenInteractor {
        get { self[ScreenInteractorKey.self] }
        set { self[ScreenInteractorKey.self] = newValue }
    }
}

private struct UnimplementedScreenInteractor: ScreenInteractor {
    var screenSelector: ScreenSelector { .main }
    var screenDebounce: Double { 5 }
    func resolveLayout() -> ScreenLayout { .init() }
}
