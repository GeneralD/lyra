import Dependencies
import Domain
import Presentation
import SwiftUI

@MainActor
public struct OverlayContentView: View {
    @ObservedObject var headerPresenter: HeaderPresenter
    @ObservedObject var lyricsPresenter: LyricsPresenter
    let rippleState: RippleState
    let screenOrigin: CGPoint

    public init(
        headerPresenter: HeaderPresenter,
        lyricsPresenter: LyricsPresenter,
        rippleState: RippleState,
        screenOrigin: CGPoint
    ) {
        self.headerPresenter = headerPresenter
        self.lyricsPresenter = lyricsPresenter
        self.rippleState = rippleState
        self.screenOrigin = screenOrigin
    }

    public var body: some View {
        ZStack {
            RippleView(rippleState: rippleState, screenOrigin: screenOrigin)
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
        withDependencies {
            $0.appStyle = .init()
        } operation: {
            OverlayContentView(
                headerPresenter: HeaderPresenter(),
                lyricsPresenter: LyricsPresenter(),
                rippleState: RippleState(),
                screenOrigin: .zero
            )
            .frame(width: 800, height: 500)
            .background(.black)
        }
    }
#endif
