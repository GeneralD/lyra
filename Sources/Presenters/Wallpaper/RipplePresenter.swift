import AppKit
import Dependencies
import Domain
import Foundation

@MainActor
public final class RipplePresenter: ObservableObject {
    public private(set) var rippleState: RippleState?
    public let screenOrigin: CGPoint
    private var mouseMonitor: Any?

    @Dependency(\.wallpaperInteractor) private var interactor

    public init(screenOrigin: CGPoint = .zero) {
        self.screenOrigin = screenOrigin
    }

    public var isEnabled: Bool { interactor.rippleConfig.enabled }
    public var rippleConfig: RippleStyle { interactor.rippleConfig }

    public func start() {
        let config = interactor.rippleConfig
        rippleState = RippleState(config: config)

        guard config.enabled else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in
                self?.rippleState?.update(screenPoint: NSEvent.mouseLocation)
            }
        }
    }

    public func stop() {
        mouseMonitor.map(NSEvent.removeMonitor)
        mouseMonitor = nil
    }

    /// Called from DisplayLink at frame rate.
    public func idle() {
        rippleState?.idle()
    }
}
