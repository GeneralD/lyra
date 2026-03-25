import Foundation

public struct AppStyle {
    public let text: TextLayout
    public let artwork: ArtworkStyle
    public let ripple: RippleStyle
    public let screen: ScreenSelector
    public let wallpaper: WallpaperStyle?
    public let configDir: String?
    public let ai: AIEndpoint?

    public init(
        text: TextLayout = .init(),
        artwork: ArtworkStyle = .init(),
        ripple: RippleStyle = .init(),
        screen: ScreenSelector = .main,
        wallpaper: WallpaperStyle? = nil,
        configDir: String? = nil,
        ai: AIEndpoint? = nil
    ) {
        self.text = text
        self.artwork = artwork
        self.ripple = ripple
        self.screen = screen
        self.wallpaper = wallpaper
        self.configDir = configDir
        self.ai = ai
    }
}

extension AppStyle: Sendable {}
