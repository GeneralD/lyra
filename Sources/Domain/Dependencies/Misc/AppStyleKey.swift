import Dependencies

public enum AppStyleKey: TestDependencyKey {
    public static let testValue: AppStyle = .init()
}

extension DependencyValues {
    public var appStyle: AppStyle {
        get { self[AppStyleKey.self] }
        set { self[AppStyleKey.self] = newValue }
    }
}
