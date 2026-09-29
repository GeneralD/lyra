import Combine
import CoreGraphics
import Dependencies
import Domain
import Foundation

/// Distinguishes which upstream fired a screen re-resolution, so the merge
/// handler can decide whether an unchanged layout still needs to be
/// reasserted (#355).
///
/// A `screenChange` signal always reasserts the layout: the window server can
/// move the actual window during reconfiguration without our model noticing
/// (#265), so it must heal on every signal regardless of value equality. A
/// poll `tick` (vacant selector or occlusion pause) carries no such healing
/// need, so it only reasserts the layout when the resolved value actually
/// changed — avoiding a periodic `onWindowFrameChange` notification for a
/// tick that changed nothing.
private enum ResolutionTrigger {
    case screenChange
    case tick
}

/// The top-level presenter managing the overlay application state and layout lifecycle.
///
/// It coordinates between the `ScreenInteractor` (which resolves geometry) and the
/// various feature presenters (Header, Lyrics, Wallpaper, Ripple).
@MainActor
public final class AppPresenter: ObservableObject {
    /// The current resolved screen layout.
    @Published public private(set) var layout: ScreenLayout = .init()

    /// Whether rendering is currently paused because the selected screen is
    /// occluded by other windows past the configured coverage threshold (#355).
    @Published public private(set) var isRenderingPaused = false

    @Dependency(\.screenInteractor) private var screenInteractor
    @Dependency(\.configInteractor) private var configInteractor
    @Dependency(\.continuousClock) private var clock

    private let ticks = PassthroughSubject<Void, Never>()
    private var pollTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    public init() {}

    /// Starts observing screen changes and periodic polling for layout and
    /// occlusion reconciliation.
    public func start() {
        let interactor = screenInteractor
        layout = interactor.resolveLayout()
        interactor.screenChanges
            .map { ResolutionTrigger.screenChange }
            .merge(with: ticks.map { ResolutionTrigger.tick })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] trigger in
                guard let self else { return }
                let state = interactor.resolveState(wasPaused: self.isRenderingPaused)
                switch trigger {
                case .screenChange: self.layout = state.layout
                case .tick: if state.layout != self.layout { self.layout = state.layout }
                }
                self.isRenderingPaused = state.isOccluded
            }
            .store(in: &cancellables)
        configInteractor.appStyleChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyConfigChange() }
            .store(in: &cancellables)
        startPollingIfNeeded()
    }

    /// Stops all background tasks and subscriptions.
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        cancellables.removeAll()
        isRenderingPaused = false
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

    /// Register a side-effect to run whenever the rendering-paused verdict
    /// actually changes (#355). Deduplicated, unlike `onWindowFrameChange`:
    /// there is no window-server drift to heal here, so repeating the same
    /// verdict would just re-trigger pause/resume side effects for nothing.
    public func onRenderingPausedChange(_ handler: @escaping @MainActor (Bool) -> Void) {
        $isRenderingPaused
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { paused in handler(paused) }
            .store(in: &cancellables)
    }

    /// Reacts to a config hot-reload ping. The screen selector, debounce, or
    /// occlusion pause settings may have changed, so re-resolve accordingly
    /// (a new selector can pick a different display; an enabled occlusion
    /// pause needs an immediate verdict rather than waiting for the next
    /// tick) and restart polling to pick up a new selector/debounce/enablement
    /// — all without a daemon restart.
    private func applyConfigChange() {
        let interactor = screenInteractor
        if interactor.occlusionPauseEnabled {
            let state = interactor.resolveState(wasPaused: isRenderingPaused)
            layout = state.layout
            isRenderingPaused = state.isOccluded
        } else {
            layout = interactor.resolveLayout()
            isRenderingPaused = false
        }
        restartPolling()
    }

    /// Cancel any in-flight poll and re-arm from the live selector/debounce/enablement.
    /// Handles all transitions: became vacant or occlusion-pause-enabled (starts),
    /// neither any more (the guard in `startPollingIfNeeded` leaves it stopped), and a
    /// changed debounce interval (restarts with the new period).
    private func restartPolling() {
        pollTask?.cancel()
        pollTask = nil
        startPollingIfNeeded()
    }

    /// Polls periodically while the selected screen can change without a system
    /// notification (`.vacant`, which re-picks a screen based on mouse position)
    /// or while occlusion pause is enabled (coverage must be re-measured even
    /// when nothing else changed) (#355).
    private func startPollingIfNeeded() {
        let interactor = screenInteractor
        guard interactor.screenSelector == .vacant || interactor.occlusionPauseEnabled else { return }
        let interval = max(interactor.screenDebounce, 1)
        let subject = ticks
        pollTask = Task { [clock] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                subject.send(())
            }
        }
    }
}
