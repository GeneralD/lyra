import AppKit
import BackdropDomain
import Dependencies
import SwiftUI

@MainActor
public struct RippleView: View {
    let rippleState: RippleState
    let screenOrigin: CGPoint

    @Dependency(\.config) private var config

    public init(rippleState: RippleState, screenOrigin: CGPoint) {
        self.rippleState = rippleState
        self.screenOrigin = screenOrigin
    }

    public var body: some View {
        let rc = config.ripple
        let baseNSColor = NSColor(hexString: rc.colorHex)

        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date
                for ripple in rippleState.ripples {
                    let elapsed = now.timeIntervalSince(ripple.startTime)
                    let dur = ripple.idle ? rc.duration * 3 : rc.duration
                    guard elapsed < dur else { continue }
                    let t = elapsed / dur
                    let easeOut = 1 - (1 - t) * (1 - t)
                    let radius = easeOut * rc.radius
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

extension NSColor {
    convenience init(hexString: String) {
        let h = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard h.count == 6 || h.count == 8,
              let value = UInt64(h, radix: 16) else {
            self.init(white: 1, alpha: 1)
            return
        }
        let r, g, b, a: CGFloat
        switch h.count {
        case 8:
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        default:
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
