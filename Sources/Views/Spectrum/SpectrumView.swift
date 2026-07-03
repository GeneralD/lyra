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
        let path = spectrumBarsPath(
            in: size, heights: presenter.binHeights(),
            barWidthRatio: style.barWidthRatio, placement: style.placement
        )
        context.fill(path, with: .style(resolver.shapeStyle(from: style.barColor)))
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

/// One path containing every visible bar, so a gradient fill spans the whole
/// bar row instead of restarting per bar.
func spectrumBarsPath(
    in size: CGSize, heights: [Float], barWidthRatio: Double, placement: SpectrumPlacement
) -> Path {
    guard !heights.isEmpty, size.width > 0, size.height > 0 else { return Path() }
    let slotWidth = size.width / CGFloat(heights.count)
    let barWidth = slotWidth * min(max(barWidthRatio, 0.05), 1)
    let inset = (slotWidth - barWidth) / 2
    let cornerRadius = min(barWidth / 4, 3)
    return heights.enumerated().reduce(into: Path()) { path, bar in
        let height = size.height * CGFloat(min(max(bar.element, 0), 1))
        guard height > 0.5 else { return }
        let rect = CGRect(
            x: slotWidth * CGFloat(bar.offset) + inset,
            y: placement == .top ? 0 : size.height - height,
            width: barWidth,
            height: height
        )
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
    }
}

#if DEBUG
    #Preview("Spectrum") {
        SpectrumView(presenter: SpectrumPresenter())
            .frame(width: 600, height: 300)
            .background(.black)
    }
#endif
