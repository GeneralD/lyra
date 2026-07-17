import Combine
import Dependencies
import Domain
import Foundation

/// Owns the `ConfigInteractor` lifecycle (arming/disarming the config-file
/// watch) and reflects `ConfigInteractor.invalidConfig` as `@Published` state
/// for observers (e.g. an error overlay Presenter watches this to know when the
/// last reload failed and the previous config is still in effect).
///
/// Fronting the interactor through its Presenter — as every other overlay does
/// (`SpectrumPresenter` owns `SpectrumInteractor.start()`/`stop()` the same way)
/// — keeps the `AppRouter` wireframe from reaching into the Interactor layer
/// directly, and lets `@Dependency` resolve the interactor in the Presenter's
/// own construction scope so `start()` and `stop()` act on the same instance.
@MainActor
public final class ConfigStatusPresenter: ObservableObject {
    @Published public private(set) var invalidConfig: ConfigReloadFailure?

    @Dependency(\.configInteractor) private var interactor
    private var cancellables: Set<AnyCancellable> = []

    public init() {}

    public func start() {
        interactor.invalidConfig
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.invalidConfig = $0 }
            .store(in: &cancellables)
        // Arm the watch only after the invalid-state subscription is live, and after AppRouter has
        // started the other `appStyleChanges` subscribers, so no reload events are missed.
    }

    public func stop() {
        interactor.stop()
        cancellables.removeAll()
    }
}
