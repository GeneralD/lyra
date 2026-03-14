import BackdropDomain
import Foundation
import Observation

@MainActor @Observable
public final class OverlayState {
    public var title: String?
    public var artist: String?
    public var artworkData: Data?
    public var lyrics: LyricsContent?
    public var activeLineIndex: Int?
    public var fetchGeneration: Int = 0
    public var screenOrigin: CGPoint = .zero

    public init() {}

    public func reset() {
        title = nil; artist = nil; artworkData = nil
        lyrics = nil; activeLineIndex = nil
        fetchGeneration += 1
    }
}
