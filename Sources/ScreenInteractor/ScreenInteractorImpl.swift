import AppKit
import Dependencies
import Domain

public struct ScreenInteractorImpl {
    @Dependency(\.configUseCase) private var configService

    public init() {}
}

extension ScreenInteractorImpl: ScreenInteractor {
    public var screenSelector: ScreenSelector {
        configService.loadAppStyle().screen
    }

    public func resolveLayout() -> ScreenLayout {
        let screen = resolveScreen()
        
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

    private func resolveScreen() -> NSScreen {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return .fallback }
        switch screenSelector {
        case .main:
            return .main ?? .fallback
        case .primary:
            return .fallback
        case .index(let n):
            return n < screens.count ? screens[n] : .fallback
        case .smallest:
            return screens.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                ?? .fallback
        case .largest:
            return screens.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                ?? .fallback
        }
    }
}

extension NSScreen {
    fileprivate static var fallback: NSScreen {
        screens.first ?? NSScreen()
    }
}
