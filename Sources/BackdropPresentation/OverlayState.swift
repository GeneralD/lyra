import BackdropDomain
import Foundation
import Observation

@MainActor @Observable
public final class OverlayState {
    public var title: FetchState<String> = .idle
    public var artist: FetchState<String> = .idle
    public var artworkData: Data?
    public var lyrics: FetchState<LyricsContent> = .idle
    public var activeLineIndex: Int?
    public var screenOrigin: CGPoint = .zero

    public init() {}
}

extension OverlayState {
    public func reset() {
        title = .idle
        artist = .idle
        artworkData = nil
        lyrics = .idle
        activeLineIndex = nil
    }
}
