import Domain
import Foundation
import Observation

@MainActor @Observable
public final class OverlayState {
    // Source data
    public var title: FetchState<String> = .idle
    public var artist: FetchState<String> = .idle
    public var artworkData: Data?
    public var lyrics: FetchState<LyricsContent> = .idle
    public var activeLineIndex: Int?
    public var screenOrigin: CGPoint = .zero

    // Display-ready strings (driven by DecodeEffectState in controller)
    public var displayTitle: String = " "
    public var displayArtist: String = " "
    public var displayLyricLines: [String] = []

    public init() {}
}

extension OverlayState {
    public func reset() {
        title = .idle
        artist = .idle
        artworkData = nil
        lyrics = .idle
        activeLineIndex = nil
        displayTitle = " "
        displayArtist = " "
        displayLyricLines = []
    }
}
