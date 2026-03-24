public struct DecodeEffect: Sendable {
    public let duration: Double
    public let charsets: Set<CharsetName>

    public init(
        duration: Double = 0.8,
        charsets: Set<CharsetName> = Set(CharsetName.allCases)
    ) {
        self.duration = duration
        self.charsets = charsets
    }
}
