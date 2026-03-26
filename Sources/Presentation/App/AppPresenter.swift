import Dependencies
import Domain
import Foundation

@MainActor
public final class AppPresenter: ObservableObject {
    @Published public private(set) var layout: ScreenLayout = .init()
    @Published public private(set) var hasWallpaper: Bool = false

    @Dependency(\.screenInteractor) private var screenInteractor

    public init() {}

    public func resolveFrames(wallpaperURL: URL?) async {
        hasWallpaper = wallpaperURL != nil
        layout = await screenInteractor.resolveLayout(wallpaperURL: wallpaperURL, hasWallpaper: hasWallpaper)
    }
}
