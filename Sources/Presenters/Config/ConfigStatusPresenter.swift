import Combine
import Dependencies
import Domain
import Foundation

/// Reflects `ConfigInteractor.invalidConfig` as `@Published` state for observers
/// (e.g. an error overlay Presenter watches this to know when the last reload
/// failed and the previous config is still in effect).
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
    }

    public func stop() {
        cancellables.removeAll()
    }
}
