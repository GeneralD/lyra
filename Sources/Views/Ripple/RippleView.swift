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
                    let commands = presenter.rippleDrawCommands(
                        canvasSize: size, now: timeline.date)
                    for cmd in commands {
                        context.stroke(
                            Path(ellipseIn: cmd.rect),
                            with: .color(
                                Color(
                                    hue: cmd.hue, saturation: cmd.saturation,
                                    brightness: cmd.brightness, opacity: cmd.opacity)),
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
