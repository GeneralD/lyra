import Presentation
import SwiftUI

@MainActor
public struct OverlayContentView: View {
    let headerPresenter: HeaderPresenter
    let lyricsPresenter: LyricsPresenter
    let ripplePresenter: RipplePresenter
    let screenOrigin: CGPoint

    public init(
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        ripplePresenter: RipplePresenter,
        screenOrigin: CGPoint
    ) {
        self.headerPresenter = headerPresenter
        self.lyricsPresenter = lyricsPresenter
        self.ripplePresenter = ripplePresenter
        self.screenOrigin = screenOrigin
    }

    public var body: some View {
        ZStack {
            RippleView(presenter: ripplePresenter, screenOrigin: screenOrigin)
            VStack(alignment: .leading, spacing: 32) {
                HeaderView(presenter: headerPresenter)
                LyricsColumnView(presenter: lyricsPresenter)
            }
            .padding(48)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

#if DEBUG
    #Preview("Overlay") {
        OverlayContentView(
            headerPresenter: HeaderPresenter(),
            lyricsPresenter: LyricsPresenter(),
            ripplePresenter: RipplePresenter(),
            screenOrigin: .zero
        )
        .frame(width: 800, height: 500)
        .background(.black)
    }
#endif
