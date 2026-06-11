import AppKit
import Combine
import CoreGraphics
import Dependencies
import Domain

public struct ScreenInteractorImpl {
    @Dependency(\.configUseCase) private var configService
    @Dependency(\.screenProvider) private var screenProvider

    public init() {}
}

extension ScreenInteractorImpl: ScreenInteractor {
    public var screenSelector: ScreenSelector {
        configService.appStyle.screen
    }

    public var screenDebounce: Double {
        configService.appStyle.screenDebounce
    }

    /// Signals that the overlay geometry may need re-resolution. Besides screen
    /// parameter changes, this includes the window being moved or resized —
    /// during display hot-plugging the window server relocates windows behind
    /// the app's back (#265), and the overlay (the process's only window) must
    /// snap back to its resolved layout. The apply side is idempotent, so the
    /// move/resize triggered by re-asserting the layout does not loop.
    public var screenChanges: AnyPublisher<Void, Never> {
        let center = NotificationCenter.default
        return center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(
                with: center.publisher(for: NSWindow.didMoveNotification),
                center.publisher(for: NSWindow.didResizeNotification)
            )
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    public func resolveLayout() -> ScreenLayout {
        guard let screen = resolveScreen() else { return .init() }

        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let hostingFrame = CGRect(
            x: visibleFrame.minX - fullFrame.minX,
            y: visibleFrame.minY - fullFrame.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        return ScreenLayout(
            windowFrame: fullFrame,
            hostingFrame: hostingFrame,
            screenOrigin: CGPoint(x: visibleFrame.minX, y: visibleFrame.minY)
        )
    }

    private func resolveScreen() -> ScreenInfo? {
        let screens = screenProvider.screens
        guard let fallback = screens.first else { return nil }
        switch screenSelector {
        case .main:
            return screenProvider.mainScreen ?? fallback
        case .primary:
            return fallback
        case .index(let n):
            return screens.indices.contains(n) ? screens[n] : fallback
        case .smallest:
            return screens.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                ?? fallback
        case .largest:
            return screens.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                ?? fallback
        case .vacant:
            return screens.min { screenProvider.windowOccupancy(for: $0) < screenProvider.windowOccupancy(for: $1) }
                ?? fallback
        }
    }
}
