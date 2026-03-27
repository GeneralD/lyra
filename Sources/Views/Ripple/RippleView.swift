import Presenters
import SwiftUI

@MainActor
public struct RippleView: View {
    let presenter: RipplePresenter

    public init(presenter: RipplePresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if presenter.isEnabled, presenter.rippleState != nil {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let commands = presenter.drawingContexts(
                        canvasSize: size, now: timeline.date)
                    for cmd in commands {
                        context.stroke(
                            Path(ellipseIn: cmd.rect),
                            with: .color(
                                red: cmd.color.red, green: cmd.color.green,
                                blue: cmd.color.blue, opacity: cmd.color.alpha),
                            lineWidth: 2.5
                        )
                    }
                }
            }
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
