import Foundation
import Presenters
import SwiftUI

@MainActor
public struct OverlayContentView: View {
    let headerPresenter: HeaderPresenter
    let lyricsPresenter: LyricsPresenter
    let ripplePresenter: RipplePresenter
    @ObservedObject var wallpaperPresenter: WallpaperPresenter

    public init(
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter,
        wallpaperPresenter: WallpaperPresenter
    ) {
        self.headerPresenter = headerPresenter
        self.lyricsPresenter = lyricsPresenter
        self.ripplePresenter = ripplePresenter
        self.wallpaperPresenter = wallpaperPresenter
    }

    public var body: some View {
        ZStack {
            RippleView(presenter: ripplePresenter)
            VStack(alignment: .leading, spacing: 32) {
                HeaderView(presenter: headerPresenter)
                LyricsColumnView(presenter: lyricsPresenter)
            }
            .padding(48)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            WallpaperLoadingOverlay(presenter: wallpaperPresenter)
        }
        .accessibilityIdentifier("overlay-content")
    }
}

private struct WallpaperLoadingOverlay: View {
    @ObservedObject var presenter: WallpaperPresenter

    var body: some View {
        // The static `ZStack` host is always in the tree, but the animated
        // `SonarLoadingIndicator` (a `TimelineView` driving a per-frame Canvas)
        // is included only while loading. Conditional inclusion — not
        // `.opacity(0)` — is mandatory: an invisible-but-present timeline keeps
        // redrawing every frame and idle-burns CPU/GPU on every machine running
        // lyra (#252). The host is removed-when-hidden in spirit: nothing inside
        // animates until the indicator is inserted.
        ZStack {
            if presenter.showLoadingIndicator {
                SonarLoadingIndicator()
                    // Centered in the overlay, clear of the top-leading lyrics
                    // (48pt inset), so it never fights the lyric column.
                    .accessibilityIdentifier("wallpaper-loading-indicator")
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: presenter.showLoadingIndicator)
    }
}

// MARK: - Sonar loading indicator

/// Indeterminate loading indicator in Lyra's visual language: gold sonar rings
/// expand and fade outward from a pulsing core, echoing the ripple effect and
/// the gold-gradient lyric highlight. Rendered on a `Canvas` driven by
/// `TimelineView(.animation)` so the motion is GPU-driven rather than
/// timer-driven, matching `RippleView`. The whole view exists only while the
/// download is in flight (see `WallpaperLoadingOverlay`), so there is no idle
/// timeline to pause here.
private struct SonarLoadingIndicator: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(&context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: SonarMetrics.diameter, height: SonarMetrics.diameter)
        .background(backing)
    }

    /// Frosted disc + faint rim + drop shadow. This self-contained contrast
    /// backing is what lets the rings read over BOTH a very bright and a very
    /// dark wallpaper instead of relying on a single fixed tint.
    private var backing: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay {
                Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = size.width / 2 - SonarMetrics.rimInset
        drawSonarRings(&context, center: center, maxRadius: maxRadius, time: time)
        drawCore(&context, center: center, time: time)
    }

    /// Concentric rings, each offset in phase, expanding from the core to the
    /// rim. Each ring is drawn twice — a soft dark halo underneath and a gold
    /// gradient core on top — so it stays legible against bright backgrounds.
    private func drawSonarRings(
        _ context: inout GraphicsContext, center: CGPoint, maxRadius: CGFloat, time: TimeInterval
    ) {
        for index in 0..<SonarMetrics.ringCount {
            let phase = (time / SonarMetrics.ringPeriod + Double(index) / Double(SonarMetrics.ringCount))
                .truncatingRemainder(dividingBy: 1)
            let radius = SonarMetrics.coreRadius + CGFloat(phase) * (maxRadius - SonarMetrics.coreRadius)
            // Symmetric fade: rings ease in near the core and out at the rim, so
            // they never pop into existence at either boundary.
            let alpha = sin(phase * .pi)
            let rect = CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let ring = Path(ellipseIn: rect)
            context.stroke(
                ring, with: .color(.black.opacity(alpha * 0.35)), lineWidth: SonarMetrics.haloLineWidth)
            context.stroke(
                ring,
                with: .linearGradient(
                    GoldSonar.faded(alpha),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ),
                lineWidth: SonarMetrics.ringLineWidth
            )
        }
    }

    /// Pulsing gold core — the "sound source" the rings emanate from.
    private func drawCore(_ context: inout GraphicsContext, center: CGPoint, time: TimeInterval) {
        let pulse = 0.85 + 0.15 * sin(time * 2 * .pi / SonarMetrics.corePulsePeriod)
        let radius = SonarMetrics.coreRadius * CGFloat(pulse)
        let rect = CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let dot = Path(ellipseIn: rect)
        context.fill(
            dot,
            with: .radialGradient(
                GoldSonar.core, center: center, startRadius: 0, endRadius: radius))
    }
}

private enum SonarMetrics {
    static let diameter: CGFloat = 120
    static let rimInset: CGFloat = 10
    static let coreRadius: CGFloat = 11
    static let ringCount = 3
    static let ringPeriod: Double = 2.4
    static let ringLineWidth: CGFloat = 2.5
    static let haloLineWidth: CGFloat = 5
    static let corePulsePeriod: Double = 1.7
}

/// Gold palette mirrored from the lyric-highlight gradient
/// (`#B8942D → #EDCF73 → #FFEB99 → #CCA64D → #A68038`) so the indicator shares
/// Lyra's signature gold identity.
private enum GoldSonar {
    static let stops: [Gradient.Stop] = [
        .init(color: Color(red: 0.722, green: 0.580, blue: 0.176), location: 0.00),
        .init(color: Color(red: 0.929, green: 0.812, blue: 0.451), location: 0.30),
        .init(color: Color(red: 1.000, green: 0.922, blue: 0.600), location: 0.55),
        .init(color: Color(red: 0.800, green: 0.651, blue: 0.302), location: 0.78),
        .init(color: Color(red: 0.651, green: 0.502, blue: 0.220), location: 1.00),
    ]

    /// Bright warm center fading to deep gold — a glowing core, not a flat dot.
    static let core = Gradient(colors: [
        Color(red: 1.000, green: 0.953, blue: 0.780),
        Color(red: 1.000, green: 0.922, blue: 0.600),
        Color(red: 0.722, green: 0.580, blue: 0.176),
    ])

    /// The gold gradient with a uniform opacity baked into every stop, so a
    /// ring can fade as it travels (gradient shadings carry no separate alpha).
    static func faded(_ alpha: Double) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.color.opacity(alpha), location: $0.location) })
    }
}

#if DEBUG
    #Preview("Overlay") {
        OverlayContentView(
            headerPresenter: HeaderPresenter(),
            lyricsPresenter: LyricsPresenter(),
            ripplePresenter: RipplePresenter(),
            wallpaperPresenter: WallpaperPresenter()
        )
        .frame(width: 800, height: 500)
        .background(.black)
    }

    #Preview("Loading Indicator") {
        // Side-by-side bright / dark stand-in wallpapers to judge that the
        // indicator reads clearly against either extreme.
        HStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [.white, Color(red: 0.95, green: 0.92, blue: 0.80)],
                    startPoint: .top, endPoint: .bottom)
                SonarLoadingIndicator()
            }
            ZStack {
                LinearGradient(
                    colors: [.black, Color(red: 0.10, green: 0.10, blue: 0.16)],
                    startPoint: .top, endPoint: .bottom)
                SonarLoadingIndicator()
            }
        }
        .frame(width: 520, height: 320)
        .ignoresSafeArea()
    }
#endif
