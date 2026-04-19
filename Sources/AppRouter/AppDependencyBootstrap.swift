@preconcurrency import Combine
import Dependencies
import Domain
import Foundation

#if DEBUG
    struct AppDependencyBootstrap {
        let launchEnvironment: AppLaunchEnvironment

        func apply(to dependencies: inout DependencyValues) {
            guard launchEnvironment.isUITestMode else { return }

            let fixture = UITestLyricsFixture(
                title: launchEnvironment.title,
                artist: launchEnvironment.artist,
                lyricsLines: launchEnvironment.lyricsLines
            )
            dependencies.screenInteractor = UITestScreenInteractor()
            dependencies.trackInteractor = UITestTrackInteractor(fixture: fixture)
            dependencies.wallpaperInteractor = UITestWallpaperInteractor()
        }
    }

    struct UITestLyricsFixture: Sendable, Equatable {
        let title: String
        let artist: String
        let lyricsLines: [String]

        var trackUpdate: TrackUpdate {
            TrackUpdate(
                title: title,
                artist: artist,
                lyrics: .plain(lyricsLines),
                lyricsState: .resolved
            )
        }
    }

    private struct UITestScreenInteractor: ScreenInteractor {
        var screenSelector: ScreenSelector { .main }
        var screenDebounce: Double { 5 }

        func resolveLayout() -> ScreenLayout {
            .init(
                windowFrame: .init(x: 0, y: 0, width: 1280, height: 720),
                hostingFrame: .init(x: 0, y: 0, width: 1280, height: 720),
                screenOrigin: .zero
            )
        }
    }

    private final class UITestTrackInteractor: TrackInteractor, @unchecked Sendable {
        let trackChange: AnyPublisher<TrackUpdate, Never>
        let artwork: AnyPublisher<Data?, Never>
        let playbackPosition: AnyPublisher<PlaybackPosition, Never>
        let decodeEffectConfig: DecodeEffect
        let textLayout: TextLayout
        let artworkStyle: ArtworkStyle

        init(fixture: UITestLyricsFixture) {
            let decodeEffect = DecodeEffect(duration: 0)
            trackChange = Just(fixture.trackUpdate).eraseToAnyPublisher()
            artwork = Just(nil).eraseToAnyPublisher()
            playbackPosition = Just(PlaybackPosition(elapsed: nil, playbackRate: 0)).eraseToAnyPublisher()
            decodeEffectConfig = decodeEffect
            textLayout = TextLayout(decodeEffect: decodeEffect)
            artworkStyle = ArtworkStyle(opacity: 0)
        }
    }

    private struct UITestWallpaperInteractor: WallpaperInteractor {
        func resolveWallpaper() async throws -> WallpaperState { .init() }
        var rippleConfig: RippleStyle { .init(enabled: false) }
    }
#else
    struct AppDependencyBootstrap {
        let launchEnvironment: AppLaunchEnvironment

        func apply(to dependencies: inout DependencyValues) {}
    }
#endif
