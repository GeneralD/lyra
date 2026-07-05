import Dependencies
import Domain
import SwiftUI

/// Canvas drawing for the spectrum analyzer (#23). Owns the irreducible
/// `GraphicsContext` side of the render — `context.fill` / `drawLayer` — so it
/// is `@MainActor` and lives apart from both the pure geometry
/// (`SpectrumGeometry`, unit-tested) and the SwiftUI view struct
/// (`SpectrumView`, declaration only). As a struct it holds its collaborators
/// (the resolver via DI, a geometry instance) rather than reaching into a
/// global namespace; the values it draws all come from the tested geometry, so
/// only the Canvas plumbing remains here — thin by design, not unit-tested.
@MainActor
struct SpectrumRenderer {
    @Dependency(\.swiftUIResolver) private var resolver
    private let geometry = SpectrumGeometry()

    init() {}

    /// Paints one spectrum frame into the Canvas: the optional background fill,
    /// then the bars derived from `heights` at the style's master opacity.
    func draw(
        _ context: inout GraphicsContext, size: CGSize, heights: [Float], style: SpectrumStyle
    ) {
        if let background = style.backgroundColor {
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(
                    red: background.red, green: background.green,
                    blue: background.blue, opacity: background.alpha)
            )
        }
        let bars = geometry.barRects(
            in: size, heights: heights,
            barWidth: style.barWidth, barSpacing: style.barSpacing, placement: style.placement,
            cornerRadius: style.barCornerRadius
        )
        guard !bars.isEmpty else { return }
        // Master bar opacity multiplies with each colour's own alpha and is
        // applied after the background fill so the two stay independent.
        context.opacity = style.barOpacity
        fill(&context, bars: bars, size: size, style: style)
    }

    /// Paints the bars per the gradient direction. A solid `bar_color` (or a
    /// gradient of one color) is a flat fill regardless of direction; a real
    /// gradient runs horizontally (`frequency`), vertically over the whole
    /// bar area VU-style (`amplitude`), or picks one flat color per bar from
    /// its height (`level`).
    private func fill(
        _ context: inout GraphicsContext, bars: [SpectrumBar], size: CGSize, style: SpectrumStyle
    ) {
        guard case .gradient(let colors) = style.barColor, colors.count > 1 else {
            context.fill(
                geometry.barsPath(bars), with: .color(resolver.solidColor(from: style.barColor)))
            return
        }
        switch style.gradientDirection {
        case .level:
            for bar in bars {
                context.fill(
                    geometry.barsPath([bar]),
                    with: .color(resolver.color(from: style.barColor, at: Double(bar.level))))
            }
        case .frequency, .amplitude:
            let (start, end) = geometry.gradientEnds(
                for: style.gradientDirection, size: size, placement: style.placement)
            context.drawLayer { layer in
                layer.clip(to: geometry.barsPath(bars))
                layer.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        resolver.gradient(from: style.barColor),
                        startPoint: start, endPoint: end))
            }
        }
    }
}
