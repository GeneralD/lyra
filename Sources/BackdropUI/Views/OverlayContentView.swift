import BackdropDomain
import BackdropPresentation
import Dependencies
import SwiftUI

@MainActor
public struct OverlayContentView: View {
    let state: OverlayState
    let rippleState: RippleState

    public init(state: OverlayState, rippleState: RippleState) {
        self.state = state
        self.rippleState = rippleState
    }

    public var body: some View {
        ZStack {
            RippleView(rippleState: rippleState, screenOrigin: state.screenOrigin)
            VStack(alignment: .leading, spacing: 32) {
                HeaderView(state: state)
                LyricsColumnView(state: state)
            }
            .padding(48)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

#Preview("Overlay") {
    withDependencies { $0.config = .init() } operation: {
        OverlayContentView(state: {
            let s = OverlayState()
            s.title = .success("See You Again")
            s.artist = .success("Wiz Khalifa")
            s.displayTitle = "See You Again"
            s.displayArtist = "Wiz Khalifa"
            let lines: [LyricLine] = [
                .init(time: 0, text: "It been a long day"),
                .init(time: 5, text: "without you my friend"),
                .init(time: 10, text: "And I will tell you all about it"),
            ]
            s.lyrics = .success(.timed(lines))
            s.displayLyricLines = lines.map(\.text)
            s.activeLineIndex = 1
            return s
        }(), rippleState: RippleState())
        .frame(width: 800, height: 500)
        .background(.black)
    }
}
