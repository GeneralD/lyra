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
    /// The palette as a SwiftUI `Gradient`, so callers can run it along any
    /// axis (spectrum's frequency / amplitude directions).
    @MainActor func gradient(from style: ColorStyle) -> Gradient
    /// The palette sampled at `fraction` (0…1), interpolating between stops —
    /// the flat per-bar color of the spectrum's `level` gradient direction.
    @MainActor func color(from style: ColorStyle, at fraction: Double) -> Color
    @MainActor func color(_ style: ColorStyle, hueShiftedBy shift: Double, opacity: Double) -> Color
    @MainActor func hsbComponents(from style: ColorStyle) -> (hue: Double, saturation: Double, brightness: Double)
    @MainActor func lineHeight(from style: TextAppearance) -> Double
}

// MARK: - DI Key

public enum SwiftUIResolverKey: DependencyKey {
    public static let liveValue: any SwiftUIResolver = SwiftUIResolverImpl()
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
    @MainActor func shapeStyle(from style: ColorStyle) -> AnyShapeStyle { .init(.white) }
    @MainActor func gradient(from style: ColorStyle) -> Gradient { Gradient(colors: [.white]) }
    @MainActor func color(from style: ColorStyle, at fraction: Double) -> Color { .white }
    @MainActor func color(_ style: ColorStyle, hueShiftedBy shift: Double, opacity: Double) -> Color { .white }
    @MainActor func hsbComponents(from style: ColorStyle) -> (hue: Double, saturation: Double, brightness: Double) { (0, 0, 1) }
    @MainActor func lineHeight(from style: TextAppearance) -> Double { style.fontSize + style.spacing * 2 }
}
