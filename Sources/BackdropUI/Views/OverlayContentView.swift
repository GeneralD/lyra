import BackdropDomain
import BackdropPresentation
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
    OverlayContentView(state: {
        let s = OverlayState()
        s.title = .success("Rusty Nail")
        s.artist = .success("X JAPAN")
        s.displayTitle = "Rusty Nail"
        s.displayArtist = "X JAPAN"
        let lines: [LyricLine] = [
            .init(time: 0, text: "錆びついた釘を"),
            .init(time: 5, text: "抜き取るように"),
            .init(time: 10, text: "心の痛みを"),
        ]
        s.lyrics = .success(.timed(lines))
        s.displayLyricLines = lines.map(\.text)
        s.activeLineIndex = 1
        return s
    }(), rippleState: RippleState())
    .frame(width: 800, height: 500)
    .background(.black)
}
