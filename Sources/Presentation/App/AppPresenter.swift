import Dependencies
import Domain
import Foundation

@MainActor
public final class AppPresenter: ObservableObject {
    @Published public private(set) var layout: ScreenLayout = .init()
    public var hasWallpaper: Bool = false

    @Dependency(\.screenInteractor) private var screenInteractor

    public init() {}

    public func resolveFrames() async {
        layout = await screenInteractor.resolveLayout(hasWallpaper: hasWallpaper)
    }
}
