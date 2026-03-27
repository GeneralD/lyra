import Dependencies
import Domain
import SwiftUI

/// Resolves Entity config types to SwiftUI rendering types.
/// Testable via DI — stub in tests to verify View behavior without SwiftUI rendering.
public protocol SwiftUIResolver: Sendable {
    @MainActor func font(from style: TextAppearance) -> Font
    @MainActor func color(from hex: String) -> Color
    @MainActor func solidColor(from style: ColorStyle) -> Color
    @MainActor func shapeStyle(from style: ColorStyle) -> AnyShapeStyle
    @MainActor func lineHeight(from style: TextAppearance) -> Double
}

// MARK: - Live Implementation

public struct LiveSwiftUIResolver: SwiftUIResolver {
    public init() {}

    @MainActor public func font(from style: TextAppearance) -> Font {
        let weight: Font.Weight =
            switch style.fontWeight.lowercased() {
            case "ultralight": .ultraLight
            case "thin": .thin
            case "light": .light
            case "medium": .medium
            case "semibold": .semibold
            case "bold": .bold
            case "heavy": .heavy
            case "black": .black
            default: .regular
            }
        return Font.custom(style.fontName, size: style.fontSize).weight(weight)
    }

    @MainActor public func color(from hex: String) -> Color {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard let value = UInt64(h, radix: 16) else { return .white }
        switch h.count {
        case 3:
            return Color(
                red: Double((value >> 8) & 0xF) / 15,
                green: Double((value >> 4) & 0xF) / 15,
                blue: Double(value & 0xF) / 15
            )
        case 6:
            return Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        case 8:
            return Color(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                opacity: Double(value & 0xFF) / 255
            )
        default:
            return .white
        }
    }

    @MainActor public func solidColor(from style: ColorStyle) -> Color {
        switch style {
        case .solid(let hex): color(from: hex)
        case .gradient(let hexColors): color(from: hexColors.first ?? "#FFFFFF")
        }
    }

    @MainActor public func shapeStyle(from style: ColorStyle) -> AnyShapeStyle {
        switch style {
        case .solid(let hex):
            return AnyShapeStyle(color(from: hex))
        case .gradient(let hexColors):
            let colors = hexColors.map { color(from: $0) }
            guard colors.count > 1 else {
                return .init(colors.first ?? .white)
            }
            let stops = colors.enumerated().map { i, c in
                Gradient.Stop(color: c, location: CGFloat(i) / CGFloat(colors.count - 1))
            }
            return .init(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
        }
    }

    @MainActor public func lineHeight(from style: TextAppearance) -> Double {
        @Dependency(\.fontMetrics) var fontMetrics
        return fontMetrics.lineHeight(
            fontName: style.fontName, fontSize: style.fontSize, spacing: style.spacing
        )
    }
}

// MARK: - DI Key

public enum SwiftUIResolverKey: DependencyKey {
    public static let liveValue: any SwiftUIResolver = LiveSwiftUIResolver()
    public static let testValue: any SwiftUIResolver = StubSwiftUIResolver()
}

extension DependencyValues {
    public var swiftUIResolver: any SwiftUIResolver {
        get { self[SwiftUIResolverKey.self] }
        set { self[SwiftUIResolverKey.self] = newValue }
    }
}

private struct StubSwiftUIResolver: SwiftUIResolver {
    @MainActor func font(from style: TextAppearance) -> Font { .system(size: style.fontSize) }
    @MainActor func color(from hex: String) -> Color { .white }
    @MainActor func solidColor(from style: ColorStyle) -> Color { .white }
    @MainActor func shapeStyle(from style: ColorStyle) -> AnyShapeStyle { AnyShapeStyle(.white) }
    @MainActor func lineHeight(from style: TextAppearance) -> Double { style.fontSize + style.spacing * 2 }
}
