public struct TextLayout: Sendable {
    public let title: TextAppearance
    public let artist: TextAppearance
    public let lyric: TextAppearance
    public let highlight: TextAppearance
    public let decodeEffect: DecodeEffect

    public init(
        title: TextAppearance = .init(fontSize: 18, fontWeight: "bold"),
        artist: TextAppearance = .init(fontWeight: "medium"),
        lyric: TextAppearance = .init(),
        highlight: TextAppearance = .init(),
        decodeEffect: DecodeEffect = .init()
    ) {
        self.title = title
        self.artist = artist
        self.lyric = lyric
        self.highlight = highlight
        self.decodeEffect = decodeEffect
    }
}
