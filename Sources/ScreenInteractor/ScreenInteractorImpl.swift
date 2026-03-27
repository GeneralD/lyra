import AppKit
import Dependencies
import Domain

public struct ScreenInteractorImpl {
    @Dependency(\.configUseCase) private var configService

    public init() {}
}

extension ScreenInteractorImpl: ScreenInteractor {
    public var screenSelector: ScreenSelector {
        configService.appStyle.screen
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

    private func resolveScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard let fallback = screens.first else { return nil }
        switch screenSelector {
        case .main:
            return .main ?? fallback
        case .primary:
            return fallback
        case .index(let n):
            return n < screens.count ? screens[n] : fallback
        case .smallest:
            return screens.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                ?? fallback
        case .largest:
            return screens.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                ?? fallback
        }
    }
}
