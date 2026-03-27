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

@preconcurrency import Combine
import Dependencies
import Domain
import Foundation
import Testing

@testable import Presenters

// MARK: - Stub

private struct StubTrackInteractor: TrackInteractor, @unchecked Sendable {
    var trackChangePublisher: AnyPublisher<TrackUpdate, Never> = Empty().eraseToAnyPublisher()
    var decodeEffectConfig: DecodeEffect = .init(duration: 0)
    var textLayout: TextLayout = .init()
    var artworkStyle: ArtworkStyle = .init()

    var trackChange: AnyPublisher<TrackUpdate, Never> { trackChangePublisher }
    var artwork: AnyPublisher<Data?, Never> { Empty().eraseToAnyPublisher() }
    var playbackPosition: AnyPublisher<PlaybackPosition, Never> { Empty().eraseToAnyPublisher() }
}

// MARK: - Helpers

@MainActor
private func waitForLyricsSuccess(_ presenter: LyricsPresenter, timeout: Duration = .seconds(3)) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        switch presenter.lyricsState {
        case .success: return
        default: try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

// MARK: - Tests

@Suite("LyricsPresenter")
struct LyricsPresenterTests {

    @Suite("start")
    struct Start {
        @MainActor
        @Test("loads lyricStyle and highlightStyle from interactor")
        func loadsStyles() {
            let customLyric = TextAppearance(fontSize: 16, fontWeight: "bold")
            let customHighlight = TextAppearance(fontSize: 16, color: .solid("#FFD700"))
            let layout = TextLayout(lyric: customLyric, highlight: customHighlight)

            withDependencies {
                $0.trackInteractor = StubTrackInteractor(textLayout: layout)
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                #expect(presenter.lyricStyle.fontSize == 16)
                #expect(presenter.lyricStyle.fontWeight == "bold")
                #expect(presenter.highlightStyle.color == .solid("#FFD700"))
            }
        }
    }

    @Suite("receive TrackUpdate")
    struct Receive {
        @MainActor
        @Test("loading state sets lyricsState to .loading")
        func loadingState() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher()
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                subject.send(TrackUpdate(lyricsState: .loading))
                try? await Task.sleep(for: .milliseconds(100))

                #expect(presenter.lyricsState.isLoading)
            }
        }

        @MainActor
        @Test("notFound sets lyricsState to .failure")
        func notFoundState() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher()
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                subject.send(TrackUpdate(lyricsState: .notFound))
                try? await Task.sleep(for: .milliseconds(100))

                #expect(presenter.lyricsState == .failure)
                #expect(presenter.displayLyricLines.isEmpty)
            }
        }

        @MainActor
        @Test("idle resets lyricsState")
        func idleState() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher()
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                // First set to loading
                subject.send(TrackUpdate(lyricsState: .loading))
                try? await Task.sleep(for: .milliseconds(100))

                // Then idle
                subject.send(TrackUpdate(lyricsState: .idle))
                try? await Task.sleep(for: .milliseconds(100))

                #expect(presenter.lyricsState.isIdle)
                #expect(presenter.displayLyricLines.isEmpty)
                #expect(presenter.activeLineIndex == nil)
            }
        }

        @MainActor
        @Test("resolved lyrics triggers reveal")
        func resolvedLyrics() async throws {
            let subject = PassthroughSubject<TrackUpdate, Never>()
            let content = LyricsContent.plain(["Line 1", "Line 2"])

            await withDependencies {
                $0.trackInteractor = StubTrackInteractor(
                    trackChangePublisher: subject.eraseToAnyPublisher(),
                    textLayout: TextLayout(decodeEffect: .init(duration: 0))
                )
            } operation: {
                let presenter = LyricsPresenter()
                presenter.start()

                subject.send(TrackUpdate(lyrics: content, lyricsState: .resolved))
                await waitForLyricsSuccess(presenter)

                #expect(presenter.lyricsState == .success(content))
                #expect(presenter.displayLyricLines.count == 2)
            }
        }
    }
}