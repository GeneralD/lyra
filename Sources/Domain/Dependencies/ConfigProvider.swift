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

// MARK: - App Style

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

public struct TextLayout: Sendable {
    public let title: TextAppearance
    public let artist: TextAppearance
    public let lyric: TextAppearance
    public let highlight: TextAppearance
    public let decodeEffect: DecodeEffect

    public init(
        title: TextAppearance = .init(fontSize: 18, fontWeight: "bold"),
        artist: TextAppearance = .init(fontWeight: "medium"),
        lyric: TextAppearance = .init(),
        highlight: TextAppearance = .init(),
        decodeEffect: DecodeEffect = .init()
    ) {
        self.title = title
        self.artist = artist
        self.lyric = lyric
        self.highlight = highlight
        self.decodeEffect = decodeEffect
    }
}

public struct TextAppearance: Sendable {
    public let spacing: Double
    public let fontName: String
    public let fontSize: Double
    public let fontWeight: String
    public let color: ColorStyle
    public let shadow: ColorStyle
    public let lineHeight: Double

    public init(
        spacing: Double = 6,
        fontName: String = ".AppleSystemUIFont",
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

public struct ArtworkStyle: Sendable {
    public let size: Double
    public let opacity: Double

    public init(size: Double = 96, opacity: Double = 1.0) {
        self.size = size
        self.opacity = opacity
    }
}

public struct RippleStyle: Sendable {
    public let enabled: Bool
    public let color: ColorStyle
    public let radius: Double
    public let duration: Double
    public let idle: Double

    public init(
        enabled: Bool = true,
        color: ColorStyle = .solid("#AAAAFFFF"),
        radius: Double = 60,
        duration: Double = 0.6,
        idle: Double = 1
    ) {
        self.enabled = enabled
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
    case cjk
}

extension CharsetName: Sendable, Codable, Hashable, CaseIterable {}

public struct DecodeEffect: Sendable {
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

public struct AIEndpoint: Sendable {
    public let endpoint: String
    public let model: String
    public let apiKey: String

    public init(endpoint: String, model: String, apiKey: String) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
    }
}

// MARK: - DependencyKey

public enum AppStyleKey: TestDependencyKey {
    public static let testValue: AppStyle = .init()
}

extension DependencyValues {
    public var appStyle: AppStyle {
        get { self[AppStyleKey.self] }
        set { self[AppStyleKey.self] = newValue }
    }
}
