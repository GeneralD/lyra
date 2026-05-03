public struct RippleStyle {
    public let enabled: Bool
    public let color: ColorStyle
    public let radius: Double
    public let duration: Double
    public let idle: Double
    public let shape: RippleShape

    public init(
        enabled: Bool = true,
        color: ColorStyle = .solid("#AAAAFFFF"),
        radius: Double = 60,
        duration: Double = 0.6,
        idle: Double = 1,
        shape: RippleShape = .default
    ) {
        self.enabled = enabled
        self.color = color
        self.radius = radius
        self.duration = duration
        self.idle = idle
        self.shape = shape
    }
}

extension RippleStyle: Sendable {}
