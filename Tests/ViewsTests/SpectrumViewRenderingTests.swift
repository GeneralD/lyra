import AppKit
import Combine
import Dependencies
import Domain
import Presenters
import SwiftUI
import Testing

@testable import Views

// Renders `SpectrumView` through a real hosting view + `ImageRenderer` so the
// Canvas draw closure — `SpectrumRenderer.draw` / `fill` — actually executes
// (the irreducible `GraphicsContext` plumbing has no other way to run). The
// values it draws are unit-tested in `SpectrumBarRectsTests`; these cases just
// drive every fill branch (solid / level / frequency / amplitude gradient, plus
// the background fill) so the plumbing is exercised, not asserted pixel-wise.
@MainActor
private func renderHosting<Content: View>(_ view: Content, size: CGSize) {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()
    // ImageRenderer materializes SwiftUI views to a CGImage, which forces
    // Canvas/TimelineView closures to run synchronously even outside a window.
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    _ = renderer.cgImage
}

/// Ticks the presenter until it surfaces bars, bounded by a tick *budget* (not
/// a wall clock) — the capturing flag hops through the main queue, so a 1 ms
/// sleep between ticks drains it while a slow CI just takes more ticks.
@MainActor
private func tickUntilBars(_ presenter: SpectrumPresenter, within maxTicks: Int = 4000) async {
    for _ in 0..<maxTicks {
        presenter.tick()
        if !presenter.binHeights().isEmpty { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
}

private final class FakeSpectrumInteractor: SpectrumInteractor, @unchecked Sendable {
    let spectrumStyle: SpectrumStyle
    let capturingSubject = CurrentValueSubject<Bool, Never>(false)
    var magnitudesValue: [Float]

    init(style: SpectrumStyle, magnitudes: [Float]) {
        self.spectrumStyle = style
        self.magnitudesValue = magnitudes
    }

    var isCapturing: AnyPublisher<Bool, Never> { capturingSubject.eraseToAnyPublisher() }
    func start() {}
    func stop() {}
    func magnitudes(barCount: Int) -> [Float] { magnitudesValue }
}

@MainActor
@Suite("SpectrumView rendering")
struct SpectrumViewRenderingTests {
    /// mono + 1 pt bar + no gap + noise_reduction 0 (passthrough) → the bar
    /// count equals the reported track length and the first captured frame
    /// shows the magnitudes verbatim, so `binHeights()` is deterministic.
    private func style(
        barColor: ColorStyle,
        gradientDirection: SpectrumGradientDirection,
        placement: SpectrumPlacement,
        backgroundColor: ColorConfig? = nil
    ) -> SpectrumStyle {
        SpectrumStyle(
            enabled: true, stereo: false, barColor: barColor,
            gradientDirection: gradientDirection, backgroundColor: backgroundColor,
            barWidth: 1, barSpacing: 0, noiseReduction: 0, placement: placement, heightRatio: 1)
    }

    /// A started, capturing presenter whose bars are populated from the given
    /// magnitudes — ready to render with a non-empty draw path.
    private func drawablePresenter(style: SpectrumStyle) async -> SpectrumPresenter {
        let interactor = FakeSpectrumInteractor(
            style: style, magnitudes: [1, 0.75, 0.5, 0.375])
        let presenter = withDependencies {
            $0.spectrumInteractor = interactor
        } operation: {
            SpectrumPresenter()
        }
        presenter.start()
        presenter.updateBarTrackLength(4)
        interactor.capturingSubject.send(true)
        await tickUntilBars(presenter)
        return presenter
    }

    @Test("multi-color gradient with level direction fills each bar, over a background")
    func levelGradientOverBackground() async {
        let presenter = await drawablePresenter(
            style: style(
                barColor: .gradient(["#101020FF", "#4080F0FF", "#F0F0FFFF"]),
                gradientDirection: .level, placement: .bottom,
                backgroundColor: ColorConfig(hex: "#00000080")))
        defer { presenter.stop() }
        #expect(!presenter.binHeights().isEmpty)
        renderHosting(SpectrumView(presenter: presenter), size: CGSize(width: 200, height: 200))
    }

    @Test("frequency gradient draws a clipped layer for horizontal placement")
    func frequencyGradientHorizontal() async {
        let presenter = await drawablePresenter(
            style: style(
                barColor: .gradient(["#101020FF", "#4080F0FF"]),
                gradientDirection: .frequency, placement: .left))
        defer { presenter.stop() }
        renderHosting(SpectrumView(presenter: presenter), size: CGSize(width: 200, height: 200))
    }

    @Test("amplitude gradient draws a clipped layer for top placement")
    func amplitudeGradientTop() async {
        let presenter = await drawablePresenter(
            style: style(
                barColor: .gradient(["#101020FF", "#4080F0FF"]),
                gradientDirection: .amplitude, placement: .top))
        defer { presenter.stop() }
        renderHosting(SpectrumView(presenter: presenter), size: CGSize(width: 200, height: 200))
    }

    @Test("solid bar color takes the flat-fill path")
    func solidColorFlatFill() async {
        let presenter = await drawablePresenter(
            style: style(
                barColor: .solid("#FFFFFFFF"), gradientDirection: .level, placement: .right))
        defer { presenter.stop() }
        renderHosting(SpectrumView(presenter: presenter), size: CGSize(width: 200, height: 200))
    }

    @Test("an enabled but silent spectrum draws the background and stops at the no-bars guard")
    func enabledSilentNoBars() {
        // No start()/tick — `binHeights()` stays empty, so the draw paints the
        // background then bails at `guard !bars.isEmpty` (the silent overlay).
        let interactor = FakeSpectrumInteractor(
            style: style(
                barColor: .solid("#FFFFFFFF"), gradientDirection: .level, placement: .bottom,
                backgroundColor: ColorConfig(hex: "#00000080")),
            magnitudes: [])
        let presenter = withDependencies {
            $0.spectrumInteractor = interactor
        } operation: {
            SpectrumPresenter()
        }
        #expect(presenter.isEnabled)
        #expect(presenter.binHeights().isEmpty)
        renderHosting(SpectrumView(presenter: presenter), size: CGSize(width: 200, height: 200))
    }
}
