/// Resolved, all-non-optional counterpart of `SpectrumConfig` (#23).
/// Produced by `ConfigRepository` and consumed by the spectrum Interactor,
/// Presenter, and View.
public struct SpectrumStyle {
    public let enabled: Bool
    public let barCount: Int
    public let barColor: ColorStyle
    public let backgroundColor: ColorConfig?
    /// Bar width as a fraction of one bar slot (bar + gap), 0–1.
    public let barWidthRatio: Double
    public let minDb: Double
    public let maxDb: Double
    /// Per-frame exponential falloff applied to bar heights, 0–1.
    public let decayRate: Double
    public let fftSize: Int
    public let placement: SpectrumPlacement
    /// Fraction of the overlay height the bars may occupy, 0–1.
    public let heightRatio: Double

    public init(
        enabled: Bool = false,
        barCount: Int = 64,
        barColor: ColorStyle = .gradient(["#1E3A5F", "#4A9EFF"]),
        backgroundColor: ColorConfig? = nil,
        barWidthRatio: Double = 0.7,
        minDb: Double = -80,
        maxDb: Double = 0,
        decayRate: Double = 0.85,
        fftSize: Int = 1024,
        placement: SpectrumPlacement = .bottom,
        heightRatio: Double = 0.25
    ) {
        self.enabled = enabled
        self.barCount = barCount
        self.barColor = barColor
        self.backgroundColor = backgroundColor
        self.barWidthRatio = barWidthRatio
        self.minDb = minDb
        self.maxDb = maxDb
        self.decayRate = decayRate
        self.fftSize = fftSize
        self.placement = placement
        self.heightRatio = heightRatio
    }
}

extension SpectrumStyle: Sendable {}
