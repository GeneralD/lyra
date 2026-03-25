public struct ArtworkStyle {
    public let size: Double
    public let opacity: Double

    public init(size: Double = 96, opacity: Double = 1.0) {
        self.size = size
        self.opacity = opacity
    }
}

extension ArtworkStyle: Sendable {}
