import Dependencies
import Domain
import SwiftUI

// Canvas drawing for the spectrum analyzer (#23). These functions own the
// irreducible `GraphicsContext` side of the render — they cannot run without a
// live Canvas context, so they stay out of both the pure geometry
// (`SpectrumGeometry.swift`, unit-tested) and the SwiftUI view struct
// (`SpectrumView.swift`, declaration only). The geometry they consume is
// fully tested; here only the `context.fill` / `drawLayer` plumbing remains.

/// Paints one spectrum frame into the Canvas: the optional background fill,
/// then the bars derived from `heights` at the style's master opacity.
@MainActor
func drawSpectrumBars(
    _ context: inout GraphicsContext, size: CGSize, heights: [Float], style: SpectrumStyle
) {
    @Dependency(\.swiftUIResolver) var resolver
    if let background = style.backgroundColor {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(
                red: background.red, green: background.green,
                blue: background.blue, opacity: background.alpha)
        )
    }
    let bars = spectrumBarRects(
        in: size, heights: heights,
        barWidth: style.barWidth, barSpacing: style.barSpacing, placement: style.placement,
        cornerRadius: style.barCornerRadius
    )
    guard !bars.isEmpty else { return }
    // Master bar opacity multiplies with each colour's own alpha and is
    // applied after the background fill so the two stay independent.
    context.opacity = style.barOpacity
    fillSpectrumBars(&context, bars: bars, size: size, style: style, resolver: resolver)
}

/// Paints the bars per the gradient direction. A solid `bar_color` (or a
/// gradient of one color) is a flat fill regardless of direction; a real
/// gradient runs horizontally (`frequency`), vertically over the whole
/// bar area VU-style (`amplitude`), or picks one flat color per bar from
/// its height (`level`).
@MainActor
func fillSpectrumBars(
    _ context: inout GraphicsContext, bars: [SpectrumBar], size: CGSize,
    style: SpectrumStyle, resolver: any SwiftUIResolver
) {
    guard case .gradient(let colors) = style.barColor, colors.count > 1 else {
        context.fill(barsPath(bars), with: .color(resolver.solidColor(from: style.barColor)))
        return
    }
    switch style.gradientDirection {
    case .level:
        for bar in bars {
            context.fill(
                barsPath([bar]),
                with: .color(resolver.color(from: style.barColor, at: Double(bar.level))))
        }
    case .frequency, .amplitude:
        let (start, end) = gradientEnds(
            for: style.gradientDirection, size: size, placement: style.placement)
        context.drawLayer { layer in
            layer.clip(to: barsPath(bars))
            layer.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    resolver.gradient(from: style.barColor),
                    startPoint: start, endPoint: end))
        }
    }
}
