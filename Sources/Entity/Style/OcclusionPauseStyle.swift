public struct OcclusionPauseStyle {
    public let enabled: Bool
    public let threshold: Double

    public init(enabled: Bool = false, threshold: Double = 0.9) {
        self.enabled = enabled
        self.threshold = threshold
    }
}

extension OcclusionPauseStyle: Sendable {}
