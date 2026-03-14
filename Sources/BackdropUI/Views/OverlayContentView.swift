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
                HeaderView(title: state.title, artist: state.artist, artworkData: state.artworkData)
                LyricsColumnView(lyrics: state.lyrics, activeLineIndex: state.activeLineIndex)
            }
            .padding(48)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
