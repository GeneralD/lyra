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
    /// - Parameters:
    ///   - previousScreen: The screen `wasPaused` was measured against on the
    ///     previous call (`ScreenState.screen` from that call), or `nil` on
    ///     the first call. A screen selector such as `.vacant` can resolve a
    ///     different screen on every call, so the hysteresis band must only
    ///     apply when the newly-resolved screen is the same one `wasPaused`
    ///     came from — otherwise a pause earned on one screen would leak its
    ///     resume-side hysteresis onto another (#355).
    ///   - wasPaused: Whether rendering was paused on `previousScreen`.
    /// - Returns: A `ScreenState` combining `resolveLayout()`'s layout with the
    ///   occlusion verdict for the same resolved screen.
    func resolveState(previousScreen: ScreenInfo?, wasPaused: Bool) -> ScreenState
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
    func resolveState(previousScreen: ScreenInfo?, wasPaused: Bool) -> ScreenState {
        ScreenState(layout: resolveLayout(), isOccluded: false)
    }
    var screenChanges: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
}
