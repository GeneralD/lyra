import Combine
import CoreGraphics
import Dependencies
import Domain
import Foundation

@MainActor
public final class AppPresenter: ObservableObject {
    @Published public private(set) var layout: ScreenLayout = .init()

    @Dependency(\.screenInteractor) private var screenInteractor
    @Dependency(\.continuousClock) private var clock

    private var vacantTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    public init() {}

    public func start() {
        recalculateLayout()
        startVacantPollingIfNeeded()
    }

    public func stop() {
        vacantTask?.cancel()
        vacantTask = nil
        cancellables.removeAll()
    }

    public func recalculateLayout() {
        layout = screenInteractor.resolveLayout()
    }

    /// Push the derived ripple rect to the presenter whenever layout changes.
    /// Keeps Combine wiring inside the Presenter layer so AppWindow stays
    /// a pure AppKit renderer.
    public func bind(ripplePresenter: RipplePresenter) {
        $layout
            .map { CGRect(origin: $0.screenOrigin, size: $0.hostingFrame.size) }
            .removeDuplicates()
            .sink { [weak ripplePresenter] rect in
                ripplePresenter?.updateScreenRect(rect)
            }
            .store(in: &cancellables)
    }

    /// Register a side-effect to run when the window frame actually changes.
    /// AppWindow uses this to call `setFrame` without owning the subscription.
    public func onWindowFrameChange(_ handler: @escaping @MainActor (ScreenLayout) -> Void) {
        $layout
            .removeDuplicates { $0.windowFrame == $1.windowFrame }
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { layout in
                MainActor.assumeIsolated { handler(layout) }
            }
            .store(in: &cancellables)
    }

    private func startVacantPollingIfNeeded() {
        guard screenInteractor.screenSelector == .vacant else { return }
        let interval = max(screenInteractor.screenDebounce, 1)
        vacantTask = Task { [weak self, clock] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                self?.recalculateLayout()
            }
        }
    }
}
