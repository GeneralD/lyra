import AppKit
import Domain
import Dependencies
import SwiftHEXColors
import SwiftUI

@MainActor
public struct RippleView: View {
    let rippleState: RippleState
    let screenOrigin: CGPoint

    @Dependency(\.appStyle) private var config

    public init(rippleState: RippleState, screenOrigin: CGPoint) {
        self.rippleState = rippleState
        self.screenOrigin = screenOrigin
    }

    public var body: some View {
        if config.ripple.enabled {
            rippleCanvas
        }
    }

    private var rippleCanvas: some View {
        let rippleConfig = config.ripple
        let baseNSColor: NSColor = {
            guard case .solid(let hex) = rippleConfig.color else { return .white }
            return (NSColor(hexString: hex) ?? .white).usingColorSpace(.deviceRGB) ?? .white
        }()

        return TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date
                for ripple in rippleState.ripples {
                    let elapsed = now.timeIntervalSince(ripple.startTime)
                    let dur = ripple.idle ? rippleConfig.duration * 3 : rippleConfig.duration
                    guard elapsed < dur else { continue }
                    let t = elapsed / dur
                    let easeOut = 1 - (1 - t) * (1 - t)
                    let radius = easeOut * rippleConfig.radius
                    let shifted = Color(
                        hue: (baseNSColor.hueComponent + ripple.hueShift).truncatingRemainder(dividingBy: 1),
                        saturation: baseNSColor.saturationComponent,
                        brightness: baseNSColor.brightnessComponent,
                        opacity: baseNSColor.alphaComponent * pow(1 - t, 0.6)
                    )
                    let x = ripple.position.x - screenOrigin.x
                    let y = size.height - (ripple.position.y - screenOrigin.y)
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(shifted),
                        lineWidth: 2.5
                    )
                }
            }
        }
    }
}


#if DEBUG
#Preview("Ripple") {
    withDependencies { $0.appStyle = .init() } operation: {
        RippleView(rippleState: RippleState(), screenOrigin: .zero)
            .frame(width: 400, height: 300)
            .background(.black)
    }
}
#endif
