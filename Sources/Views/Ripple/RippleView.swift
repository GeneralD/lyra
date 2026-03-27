// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import AppKit
import Domain
import Presenters
import SwiftUI

@MainActor
public struct RippleView: View {
    let presenter: RipplePresenter

    public init(presenter: RipplePresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        if presenter.isEnabled, let rippleState = presenter.rippleState {
            rippleCanvas(rippleState: rippleState, config: presenter.rippleConfig)
        }
    }

    private func rippleCanvas(rippleState: RippleState, config: RippleStyle) -> some View {
        let screenOrigin = presenter.screenOrigin
        let baseNSColor: NSColor = {
            guard case .solid(let hex) = config.color else { return .white }
            let color = parseHexColor(hex)
            return NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        }()

        return TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date
                for ripple in rippleState.ripples {
                    let elapsed = now.timeIntervalSince(ripple.startTime)
                    let dur = ripple.idle ? config.duration * 3 : config.duration
                    guard elapsed < dur else { continue }
                    let t = elapsed / dur
                    let easeOut = 1 - (1 - t) * (1 - t)
                    let radius = easeOut * config.radius
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
        RippleView(presenter: RipplePresenter())
            .frame(width: 400, height: 300)
            .background(.black)
    }
#endif