import AppKit
import CoreGraphics
import Domain

public struct AppKitScreenProvider {
    private let windowInfoList: @Sendable () -> [[String: Any]]?

    public init() {
        self.init(windowInfoList: {
            CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]]
        })
    }

    init(windowInfoList: @escaping @Sendable () -> [[String: Any]]?) {
        self.windowInfoList = windowInfoList
    }
}

extension AppKitScreenProvider: ScreenProvider {
    public var screens: [ScreenInfo] {
        NSScreen.screens.map { ScreenInfo(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    public var mainScreen: ScreenInfo? {
        NSScreen.main.map { ScreenInfo(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    public func windowOccupancy(for screen: ScreenInfo) -> Double {
        screen.occupancy(windows: visibleWindowBounds())
    }

    public func windowCoverage(for screen: ScreenInfo) -> Double {
        screen.coverage(windows: visibleWindowBounds())
    }

    private func visibleWindowBounds() -> [CGRect] {
        guard let infoList = windowInfoList() else { return [] }
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return infoList.compactMap { info -> CGRect? in
            guard
                let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                let pid = info[kCGWindowOwnerPID as String] as? Int, pid != myPID,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            var cgRect = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds, &cgRect), cgRect.width > 0, cgRect.height > 0
            else { return nil }
            return cgRect.flippedToAppKit(primaryHeight: primaryHeight)
        }
    }
}
