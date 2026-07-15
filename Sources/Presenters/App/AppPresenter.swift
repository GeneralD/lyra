import Combine
import CoreGraphics
import Dependencies
import Domain
import Foundation

/// The top-level presenter managing the overlay application state and layout lifecycle.
///
/// It coordinates between the `ScreenInteractor` (which resolves geometry) and the
/// various feature presenters (Header, Lyrics, Wallpaper, Ripple).
@MainActor
public final class AppPresenter: ObservableObject {
    /// The current resolved screen layout.
    @Published public private(set) var layout: ScreenLayout = .init()

    @Dependency(\.screenInteractor) private var screenInteractor
    @Dependency(\.configInteractor) private var configInteractor
    @Dependency(\.continuousClock) private var clock

    private let vacantTicks = PassthroughSubject<Void, Never>()
    private var vacantTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    public init() {}

    /// Starts observing screen changes and periodic polling for layout reconciliation.
    public func start() {
        let interactor = screenInteractor
        layout = interactor.resolveLayout()
        interactor.screenChanges
            .merge(with: vacantTicks)
            .receive(on: DispatchQueue.main)
            .map { interactor.resolveLayout() }
            .sink { [weak self] layout in self?.layout = layout }
            .store(in: &cancellables)
        configInteractor.appStyleChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyConfigChange() }
            .store(in: &cancellables)
        startVacantPollingIfNeeded()
    }

    /// Stops all background tasks and subscriptions.
    public func stop() {
        vacantTask?.cancel()
        vacantTask = nil
        cancellables.removeAll()
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

    /// Register a side-effect to run on every resolved layout, so the window
    /// geometry is re-asserted even when the resolved frame is unchanged.
    /// Deduplicating here broke recovery from display hot-plugging (#265):
    /// the window server moves the actual window during reconfiguration, and a
    /// model-value comparison cannot see that drift. The wireframe uses this
    /// to drive `OverlayWindow.applyLayout` (idempotent) without owning the
    /// subscription.
    public func onWindowFrameChange(_ handler: @escaping @MainActor (ScreenLayout) -> Void) {
        $layout
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { layout in handler(layout) }
            .store(in: &cancellables)
    }

    /// Reacts to a config hot-reload ping. The screen selector or debounce may
    /// have changed, so re-resolve the layout (a new selector can pick a
    /// different display) and restart vacant polling to pick up a new
    /// selector/debounce — all without a daemon restart.
    private func applyConfigChange() {
        layout = screenInteractor.resolveLayout()
        restartVacantPolling()
    }

    /// Cancel any in-flight vacant poll and re-arm from the live selector/debounce.
    /// Handles all three transitions: became vacant (starts), no longer vacant
    /// (the guard in `startVacantPollingIfNeeded` leaves it stopped), and a
    /// changed debounce interval (restarts with the new period).
    private func restartVacantPolling() {
        vacantTask?.cancel()
        vacantTask = nil
        startVacantPollingIfNeeded()
    }

    private func startVacantPollingIfNeeded() {
        guard screenInteractor.screenSelector == .vacant else { return }
        let interval = max(screenInteractor.screenDebounce, 1)
        let subject = vacantTicks
        vacantTask = Task { [clock] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                subject.send(())
            }
        }
    }
}
