import AppKit
import Domain

public struct AppKitScreenProvider {
    public init() {}
}

extension AppKitScreenProvider: ScreenProvider {
    public var screens: [ScreenInfo] {
        NSScreen.screens.map { ScreenInfo(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    public var mainScreen: ScreenInfo? {
        NSScreen.main.map { ScreenInfo(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }
}
