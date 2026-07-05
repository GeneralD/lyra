import Presenters
import SwiftUI

/// Bar-graph rendering of the spectrum analyzer (#23). Pure rendering: bar
/// heights, decay, and capture state all live in `SpectrumPresenter`; the bar
/// geometry lives in `SpectrumGeometry.swift` and the Canvas drawing in
/// `SpectrumRendering.swift`. This file keeps only the SwiftUI view struct.
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
                        drawSpectrumBars(
                            &context, size: size, heights: presenter.binHeights(), style: style)
                    }
                }
                // Constrain the strip to its growth depth on the edge it
                // anchors to — height for vertical placements, width for the
                // horizontal ones — then pin it against that edge.
                .frame(
                    width: isHorizontal(style.placement)
                        ? barStripDepth(in: proxy.size, style: style) : nil,
                    height: isHorizontal(style.placement)
                        ? nil : barStripDepth(in: proxy.size, style: style)
                )
                .frame(
                    maxWidth: .infinity, maxHeight: .infinity,
                    alignment: spectrumAlignment(for: style.placement)
                )
                // The bar count is derived from the track length (cava style),
                // so keep the Presenter in sync as the overlay resizes.
                .onChange(of: trackExtent(of: proxy.size, placement: style.placement), initial: true) { _, length in
                    presenter.updateBarTrackLength(length)
                }
            }
            .allowsHitTesting(false)
            .accessibilityIdentifier("spectrum-view")
        }
    }
}

#if DEBUG
    #Preview("Spectrum") {
        SpectrumView(presenter: SpectrumPresenter())
            .frame(width: 600, height: 300)
            .background(.black)
    }
#endif
