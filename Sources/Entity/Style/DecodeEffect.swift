public struct DecodeEffect {
    public let duration: Double
    public let charsets: Set<CharsetName>
    /// Text color used while the AI extractor is resolving title/artist
    /// (cache miss): the header scrambles in this color until the API responds,
    /// then settles to the resolved text in its normal color (#57).
    public let processingColor: ColorStyle

    public init(
        duration: Double = 0.8,
        charsets: Set<CharsetName> = Set(CharsetName.allCases),
        processingColor: ColorStyle = .solid("#4ADE80FF")
    ) {
        self.duration = duration
        self.charsets = charsets
        self.processingColor = processingColor
    }
}

extension DecodeEffect: Sendable {}
