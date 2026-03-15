import Dependencies
import Foundation

// MARK: - Color abstraction (UI-independent)

public enum ColorStyle {
    case solid(String)
    case gradient([String])
}

extension ColorStyle: Sendable, Equatable {}

extension ColorStyle: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .solid(str)
            return
        }
        let arr = try container.decode([String].self)
        self = arr.count == 1 ? .solid(arr[0]) : .gradient(arr)
    }
}

extension ColorStyle: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .solid(let hex): try container.encode(hex)
        case .gradient(let hexes): try container.encode(hexes)
        }
    }
}

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
    public let decodeEffect: ResolvedDecodeEffectConfig

    public init(
        title: ResolvedTextStyle = .init(fontSize: 18, fontWeight: "bold"),
        artist: ResolvedTextStyle = .init(fontWeight: "medium"),
        lyric: ResolvedTextStyle = .init(),
        highlight: ResolvedTextStyle = .init(),
        decodeEffect: ResolvedDecodeEffectConfig = .init()
    ) {
        self.title = title
        self.artist = artist
        self.lyric = lyric
        self.highlight = highlight
        self.decodeEffect = decodeEffect
    }
}

public struct ResolvedTextStyle: Sendable {
    public let spacing: Double
    public let fontName: String
    public let fontSize: Double
    public let fontWeight: String
    public let color: ColorStyle
    public let shadow: ColorStyle
    public let lineHeight: Double

    public init(
        spacing: Double = 6,
        fontName: String = "Zen Maru Gothic",
        fontSize: Double = 12,
        fontWeight: String = "regular",
        color: ColorStyle = .solid("#FFFFFFD9"),
        shadow: ColorStyle = .solid("#000000E6"),
        lineHeight: Double = 24
    ) {
        self.spacing = spacing
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.color = color
        self.shadow = shadow
        self.lineHeight = lineHeight
    }
}

public struct ResolvedArtworkConfig: Sendable {
    public let size: Double
    public let opacity: Double

    public init(size: Double = 96, opacity: Double = 1.0) {
        self.size = size
        self.opacity = opacity
    }
}

public struct ResolvedRippleConfig: Sendable {
    public let color: ColorStyle
    public let radius: Double
    public let duration: Double
    public let idle: Double

    public init(
        color: ColorStyle = .solid("#AAAAFFFF"),
        radius: Double = 60,
        duration: Double = 0.6,
        idle: Double = 1
    ) {
        self.color = color
        self.radius = radius
        self.duration = duration
        self.idle = idle
    }
}

public enum CharsetName: String {
    case latin
    case cyrillic
    case greek
    case symbols
}

extension CharsetName: Sendable, Codable, Hashable, CaseIterable {}

public struct ResolvedDecodeEffectConfig: Sendable {
    public let duration: Double
    public let charsets: Set<CharsetName>

    public init(
        duration: Double = 0.8,
        charsets: Set<CharsetName> = Set(CharsetName.allCases)
    ) {
        self.duration = duration
        self.charsets = charsets
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
