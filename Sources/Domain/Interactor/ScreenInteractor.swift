import Combine
import Dependencies

public protocol ScreenInteractor: Sendable {
    var screenSelector: ScreenSelector { get }
    var screenDebounce: Double { get }
    /// Whether occlusion pause is enabled in configuration (#355).
    var occlusionPauseEnabled: Bool { get }
    func resolveLayout() -> ScreenLayout
    /// Resolves the current screen layout and occlusion state in a single pass.
    ///
    /// - Parameter wasPaused: Whether rendering is currently paused, so the
    ///   hysteresis band can be applied on the resume side.
    /// - Returns: A `ScreenState` combining `resolveLayout()`'s layout with the
    ///   occlusion verdict for the same resolved screen.
    func resolveState(wasPaused: Bool) -> ScreenState
    /// Emits when the system's screen configuration changes
    /// (e.g. a display is connected, disconnected, or reconfigured).
    /// Provider layer adapts the platform-native notification into a Publisher
    /// so the Presenter stays AppKit-free.
    var screenChanges: AnyPublisher<Void, Never> { get }
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
    var occlusionPauseEnabled: Bool { false }
    func resolveLayout() -> ScreenLayout { .init() }
    func resolveState(wasPaused: Bool) -> ScreenState { ScreenState(layout: resolveLayout(), isOccluded: false) }
    var screenChanges: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
}
