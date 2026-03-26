@preconcurrency import AVFoundation
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

    public func resolveLayout(wallpaperURL: URL?, hasWallpaper: Bool) async -> ScreenLayout {
        let screen = await resolveScreen(wallpaperURL: wallpaperURL)
        let visibleFrame = screen.visibleFrame
        let fullFrame = screen.frame
        let windowRect = hasWallpaper ? fullFrame : visibleFrame
        let hostingFrame = CGRect(
            x: visibleFrame.minX - windowRect.minX,
            y: visibleFrame.minY - windowRect.minY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        return ScreenLayout(
            windowFrame: windowRect,
            hostingFrame: hostingFrame,
            screenOrigin: CGPoint(x: visibleFrame.minX, y: visibleFrame.minY)
        )
    }

    private func resolveScreen(wallpaperURL: URL?) async -> NSScreen {
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
        case .match:
            guard let url = wallpaperURL else { return .main ?? .fallback }
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first
            else { return .main ?? .fallback }
            let naturalSize = try? await track.load(.naturalSize)
            let transform = try? await track.load(.preferredTransform)
            guard let naturalSize, let transform else { return .main ?? .fallback }
            let size = naturalSize.applying(transform)
            let videoAspect = abs(size.width) / abs(size.height)
            return screens.min { a, b in
                let aa = a.frame.width / a.frame.height
                let ba = b.frame.width / b.frame.height
                return abs(aa - videoAspect) < abs(ba - videoAspect)
            } ?? .fallback
        }
    }
}

extension NSScreen {
    fileprivate static var fallback: NSScreen {
        screens.first ?? NSScreen()
    }
}
