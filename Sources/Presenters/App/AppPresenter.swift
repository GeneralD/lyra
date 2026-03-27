import Dependencies
import Domain
import Foundation

@MainActor
public final class AppPresenter: ObservableObject {
    @Published public private(set) var layout: ScreenLayout = .init()

    @Dependency(\.screenInteractor) private var screenInteractor

    public init() {}

    public func start() {
        recalculateLayout()
    }

    public func recalculateLayout() {
        layout = screenInteractor.resolveLayout()
    }
}
