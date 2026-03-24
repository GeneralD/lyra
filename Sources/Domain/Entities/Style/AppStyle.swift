import Foundation

public struct AppStyle: Sendable {
    public let text: TextLayout
    public let artwork: ArtworkStyle
    public let ripple: RippleStyle
    public let screen: ScreenSelector
    public let wallpaperURL: URL?
    public let ai: AIEndpoint?

    public init(
        text: TextLayout = .init(),
        artwork: ArtworkStyle = .init(),
        ripple: RippleStyle = .init(),
        screen: ScreenSelector = .main,
        wallpaperURL: URL? = nil,
        ai: AIEndpoint? = nil
    ) {
        self.text = text
        self.artwork = artwork
        self.ripple = ripple
        self.screen = screen
        self.wallpaperURL = wallpaperURL
        self.ai = ai
    }
}
