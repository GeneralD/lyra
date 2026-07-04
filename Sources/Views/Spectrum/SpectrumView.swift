import Dependencies
import Domain
import Presenters
import SwiftUI

/// Bar-graph rendering of the spectrum analyzer (#23). Pure rendering: bar
/// heights, decay, and capture state all live in `SpectrumPresenter`.
@MainActor
public struct SpectrumView: View {
    @ObservedObject var presenter: SpectrumPresenter

    public init(presenter: SpectrumPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if presenter.isEnabled {
            let style = presenter.style
            GeometryReader { proxy in
                // Pause the per-frame timeline while nothing is captured and
                // every bar has decayed away, so an enabled-but-silent
                // spectrum stops redrawing the Canvas (#252 / #258 pattern).
                TimelineView(.animation(paused: !presenter.isAnimating)) { timeline in
                    Canvas { context, size in
                        // Capturing the timeline's date ties the Canvas to the
                        // frame schedule; the bar data itself advances on the
                        // DisplayLink tick in the Presenter.
                        let _ = timeline.date
                        drawBars(&context, size: size, style: style)
                    }
                }
                .frame(height: barAreaHeight(in: proxy.size, style: style))
                .frame(
                    maxWidth: .infinity, maxHeight: .infinity,
                    alignment: Self.alignment(for: style.placement)
                )
            }
            .allowsHitTesting(false)
            .accessibilityIdentifier("spectrum-view")
        }
    }

    @MainActor
    private func drawBars(_ context: inout GraphicsContext, size: CGSize, style: SpectrumStyle) {
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
            in: size, heights: presenter.binHeights(),
            barWidthRatio: style.barWidthRatio, placement: style.placement
        )
        guard !bars.isEmpty else { return }
        fillBars(&context, bars: bars, size: size, style: style, resolver: resolver)
    }

    /// Paints the bars per the gradient direction. A solid `bar_color` (or a
    /// gradient of one color) is a flat fill regardless of direction; a real
    /// gradient runs horizontally (`frequency`), vertically over the whole
    /// bar area VU-style (`amplitude`), or picks one flat color per bar from
    /// its height (`level`).
    @MainActor
    private func fillBars(
        _ context: inout GraphicsContext, bars: [SpectrumBar], size: CGSize,
        style: SpectrumStyle, resolver: any SwiftUIResolver
    ) {
        guard case .gradient(let colors) = style.barColor, colors.count > 1 else {
            context.fill(barsPath(bars), with: .color(resolver.solidColor(from: style.barColor)))
            return
        }
        switch style.gradientDirection {
        case .level:
            bars.forEach { bar in
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

    /// Endpoints of the whole-area gradient: horizontal for `frequency`,
    /// vertical for `amplitude` — pointing from the bars' base to their tips
    /// so the high colors always land at the growing edge.
    private func gradientEnds(
        for direction: SpectrumGradientDirection, size: CGSize, placement: SpectrumPlacement
    ) -> (CGPoint, CGPoint) {
        switch direction {
        case .frequency:
            return (CGPoint(x: 0, y: size.height / 2), CGPoint(x: size.width, y: size.height / 2))
        case .amplitude:
            let base = placement == .top ? 0 : size.height
            let tip = placement == .top ? size.height : 0
            return (CGPoint(x: size.width / 2, y: base), CGPoint(x: size.width / 2, y: tip))
        case .level:
            return (.zero, .zero)
        }
    }

    private func barAreaHeight(in available: CGSize, style: SpectrumStyle) -> CGFloat {
        switch style.placement {
        case .underlay: available.height
        case .bottom, .top: available.height * min(max(style.heightRatio, 0), 1)
        }
    }

    static func alignment(for placement: SpectrumPlacement) -> Alignment {
        switch placement {
        case .bottom, .underlay: .bottom
        case .top: .top
        }
    }
}

/// One visible bar: its rounded rect and its 0…1 height, used to pick the
/// per-bar color in the `level` gradient direction.
struct SpectrumBar: Equatable {
    let rect: CGRect
    let cornerRadius: CGFloat
    let level: Float
}

/// The visible bars of the current frame — those tall enough to draw — laid
/// out across the width. Bars below half a point are dropped so the path
/// carries no invisible slivers.
func spectrumBarRects(
    in size: CGSize, heights: [Float], barWidthRatio: Double, placement: SpectrumPlacement
) -> [SpectrumBar] {
    guard !heights.isEmpty, size.width > 0, size.height > 0 else { return [] }
    let slotWidth = size.width / CGFloat(heights.count)
    let barWidth = slotWidth * min(max(barWidthRatio, 0.05), 1)
    let inset = (slotWidth - barWidth) / 2
    let cornerRadius = min(barWidth / 4, 3)
    return heights.enumerated().compactMap { bar in
        let level = min(max(bar.element, 0), 1)
        let height = size.height * CGFloat(level)
        guard height > 0.5 else { return nil }
        let rect = CGRect(
            x: slotWidth * CGFloat(bar.offset) + inset,
            y: placement == .top ? 0 : size.height - height,
            width: barWidth,
            height: height
        )
        return SpectrumBar(rect: rect, cornerRadius: cornerRadius, level: level)
    }
}

/// One path over the given bars, so a single gradient fill spans them all
/// instead of restarting per bar.
func barsPath(_ bars: [SpectrumBar]) -> Path {
    bars.reduce(into: Path()) { path, bar in
        path.addRoundedRect(
            in: bar.rect, cornerSize: CGSize(width: bar.cornerRadius, height: bar.cornerRadius))
    }
}

#if DEBUG
    #Preview("Spectrum") {
        SpectrumView(presenter: SpectrumPresenter())
            .frame(width: 600, height: 300)
            .background(.black)
    }
#endif
