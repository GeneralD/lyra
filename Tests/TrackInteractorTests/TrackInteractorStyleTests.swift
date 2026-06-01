@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import TrackInteractor

// MARK: - Stubs

private final class StubPlaybackUseCase: PlaybackUseCase, @unchecked Sendable {
    let subject = CurrentValueSubject<NowPlaying?, Never>(nil)

    func fetchNowPlaying() async -> NowPlaying? { nil }

    func observeNowPlaying() -> AsyncStream<NowPlaying?> {
        AsyncStream { continuation in
            let cancellable = subject.sink(
                receiveCompletion: { _ in continuation.finish() },
                receiveValue: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    func elapsedTime(for np: NowPlaying) -> TimeInterval? { np.rawElapsed }
}

private struct InstantMetadataUseCase: MetadataUseCase, Sendable {
    func resolve(track: Track) async -> Track? { nil }
    func resolveCandidates(track: Track) async -> [Track] { [] }
}

private struct StubLyricsUseCase: LyricsUseCase, Sendable {
    func fetchLyrics(track: Track) async -> LyricsResult { LyricsResult() }
    func fetchLyrics(candidates: [Track]) async -> LyricsResult { LyricsResult() }
    func parseLyricsContent(from result: LyricsResult?) -> LyricsContent? { nil }
}

private struct StubConfigUseCase: ConfigUseCase, Sendable {
    let style: AppStyle
    var appStyle: AppStyle { style }
    func template(format: ConfigFormat) -> String? { nil }
    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String { "" }
    var existingConfigPath: String? { nil }
}

// MARK: - Helpers

private func makeInteractor(config: any ConfigUseCase = StubConfigUseCase(style: AppStyle())) -> TrackInteractorImpl {
    withDependencies {
        $0.continuousClock = ImmediateClock()
        $0.playbackUseCase = StubPlaybackUseCase()
        $0.metadataUseCase = InstantMetadataUseCase()
        $0.lyricsUseCase = StubLyricsUseCase()
        $0.configUseCase = config
    } operation: {
        TrackInteractorImpl()
    }
}

// MARK: - Tests

@Suite("TrackInteractor style computed properties", .serialized)
struct TrackInteractorStyleTests {

    @Test("decodeEffectConfig exposes AppStyle.text.decodeEffect")
    func decodeEffectConfigReturnsConfigValue() {
        let decode = DecodeEffect(duration: 1.7)
        let style = AppStyle(text: TextLayout(decodeEffect: decode))
        let interactor = makeInteractor(config: StubConfigUseCase(style: style))

        #expect(interactor.decodeEffectConfig.duration == 1.7)
    }

    @Test("textLayout exposes AppStyle.text")
    func textLayoutReturnsConfigValue() {
        let decode = DecodeEffect(duration: 2.3)
        let style = AppStyle(text: TextLayout(decodeEffect: decode))
        let interactor = makeInteractor(config: StubConfigUseCase(style: style))

        #expect(interactor.textLayout.decodeEffect.duration == 2.3)
    }

    @Test("artworkStyle exposes AppStyle.artwork")
    func artworkStyleReturnsConfigValue() {
        let artwork = ArtworkStyle(size: 128, opacity: 0.6)
        let style = AppStyle(artwork: artwork)
        let interactor = makeInteractor(config: StubConfigUseCase(style: style))

        #expect(interactor.artworkStyle.size == 128)
        #expect(interactor.artworkStyle.opacity == 0.6)
    }

    @Test("default AppStyle values flow through to computed properties")
    func defaultsFlowThrough() {
        let interactor = makeInteractor()

        #expect(interactor.decodeEffectConfig.duration == 0.8)
        #expect(interactor.textLayout.decodeEffect.duration == 0.8)
        #expect(interactor.artworkStyle.size == 96)
        #expect(interactor.artworkStyle.opacity == 1.0)
    }
}
