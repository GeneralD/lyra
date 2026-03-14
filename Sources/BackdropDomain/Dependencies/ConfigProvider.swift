import Dependencies
import Foundation

// MARK: - Resolved config value types (pre-computed, Sendable)

public struct ResolvedConfig: Sendable {
    public let text: ResolvedTextConfig
    public let artwork: ResolvedArtworkConfig
    public let ripple: ResolvedRippleConfig
    public let screen: ScreenSelector
    public let wallpaperURL: URL?

    public init(
        text: ResolvedTextConfig = .init(),
        artwork: ResolvedArtworkConfig = .init(),
        ripple: ResolvedRippleConfig = .init(),
        screen: ScreenSelector = .main,
        wallpaperURL: URL? = nil
    ) {
        self.text = text
        self.artwork = artwork
        self.ripple = ripple
        self.screen = screen
        self.wallpaperURL = wallpaperURL
    }
}

public struct ResolvedTextConfig: Sendable {
    public let title: ResolvedTextStyle
    public let artist: ResolvedTextStyle
    public let lyric: ResolvedTextStyle
    public let highlight: ResolvedTextStyle
    public let highlightColors: [String]

    public init(
        title: ResolvedTextStyle = .init(fontSize: 18, fontWeight: "bold"),
        artist: ResolvedTextStyle = .init(fontWeight: "medium"),
        lyric: ResolvedTextStyle = .init(),
        highlight: ResolvedTextStyle = .init(),
        highlightColors: [String] = ["#B8942DFF", "#EDCF73FF", "#FFEB99FF", "#CCA64DFF", "#A68038FF"]
    ) {
        self.title = title
        self.artist = artist
        self.lyric = lyric
        self.highlight = highlight
        self.highlightColors = highlightColors
    }
}

public struct ResolvedTextStyle: Sendable {
    public let spacing: Double
    public let fontName: String
    public let fontSize: Double
    public let fontWeight: String
    public let colorHex: String
    public let shadowHex: String
    public let lineHeight: Double

    public init(
        spacing: Double = 6,
        fontName: String = "Zen Maru Gothic",
        fontSize: Double = 12,
        fontWeight: String = "regular",
        colorHex: String = "#FFFFFFD9",
        shadowHex: String = "#000000E6",
        lineHeight: Double = 24
    ) {
        self.spacing = spacing
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.colorHex = colorHex
        self.shadowHex = shadowHex
        self.lineHeight = lineHeight
    }
}

public struct ResolvedArtworkConfig: Sendable {
    public let size: Double

    public init(size: Double = 96) {
        self.size = size
    }
}

public struct ResolvedRippleConfig: Sendable {
    public let colorHex: String
    public let radius: Double
    public let duration: Double
    public let idle: Double

    public init(
        colorHex: String = "#AAAAFFFF",
        radius: Double = 60,
        duration: Double = 0.6,
        idle: Double = 1
    ) {
        self.colorHex = colorHex
        self.radius = radius
        self.duration = duration
        self.idle = idle
    }
}

// MARK: - DependencyKey

public enum ConfigKey: TestDependencyKey {
    public static let testValue: ResolvedConfig = .init()
}

extension DependencyValues {
    public var config: ResolvedConfig {
        get { self[ConfigKey.self] }
        set { self[ConfigKey.self] = newValue }
    }
}
