import Domain
import Foundation
import Presenters
import SwiftUI

@MainActor
public struct RippleView: View {
    @ObservedObject var presenter: RipplePresenter

    public init(presenter: RipplePresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if presenter.isEnabled, presenter.rippleState != nil {
            // Pause the per-frame timeline while no ripple is alive so an
            // enabled-but-idle ripple layer stops redrawing the Canvas every
            // frame (#258). A paused TimelineView still renders the current
            // frame once, so seeded-ripple Canvas tests keep exercising stroke().
            TimelineView(.animation(paused: !presenter.isAnimating)) { timeline in
                Canvas { context, size in
                    let commands = presenter.drawingContexts(
                        canvasSize: size, now: timeline.date)
                    for cmd in commands {
                        context.stroke(
                            ripplePath(in: cmd.rect, shape: cmd.shape),
                            with: .color(
                                red: cmd.color.red, green: cmd.color.green,
                                blue: cmd.color.blue, opacity: cmd.color.alpha),
                            lineWidth: 2.5
                        )
                    }
                }
            }
            .accessibilityIdentifier("ripple-view")
        }
    }
}

func ripplePath(in rect: CGRect, shape: RippleShape) -> Path {
    switch shape {
    case .circle:
        return Path(ellipseIn: rect)
    case .polygon(let rawSides, let angle):
        // Defense in depth: enum case is publicly constructable, so a non-decoder
        // caller could pass sides outside the valid range. Fall back to a circle
        // rather than crashing on `0..<negative`.
        guard rawSides >= RippleShape.minimumPolygonSides else {
            return Path(ellipseIn: rect)
        }
        let sides = min(rawSides, RippleShape.maximumPolygonSides)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startTheta = angle * .pi / 180 - .pi / 2
        let step = 2 * .pi / Double(sides)
        let points = (0..<sides).map { i -> CGPoint in
            let theta = startTheta + Double(i) * step
            return CGPoint(
                x: center.x + radius * cos(theta),
                y: center.y + radius * sin(theta))
        }
        return Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
    }
}

#if DEBUG
    #Preview("Ripple") {
        RippleView(presenter: RipplePresenter())
            .frame(width: 400, height: 300)
            .background(.black)
    }
#endif
