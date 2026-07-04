/// Resolved, all-non-optional counterpart of `SpectrumConfig` (#23).
/// Produced by `ConfigRepository` and consumed by the spectrum Interactor,
/// Presenter, and View.
public struct SpectrumStyle {
    public let enabled: Bool
    /// Splits the bar row into the two capture channels, cava-style: the
    /// left channel mirrored on the left half, the right channel on the
    /// right half, lowest frequencies meeting in the center. `false`
    /// averages both channels into one mono row.
    public let stereo: Bool
    /// Total displayed bars. Forced even by `ConfigRepository` when
    /// `stereo`, so each channel owns exactly half.
    public let barCount: Int
    public let barColor: ColorStyle
    public let backgroundColor: ColorConfig?
    /// Bar width as a fraction of one bar slot (bar + gap), 0–1.
    public let barWidthRatio: Double
    public let minDb: Double
    public let maxDb: Double
    /// Height scale of the bars: `linear` (cava's look) or `db` (flatter).
    public let scale: SpectrumScale
    /// Motion smoothing 0–1 (resolved from the 0–100 config scale): the
    /// leaky-integral memory of the bar filter and the gravity scaling of
    /// the release.
    public let noiseReduction: Double
    public let fftSize: Int
    public let placement: SpectrumPlacement
    /// Fraction of the overlay height the bars may occupy, 0–1.
    public let heightRatio: Double

    public init(
        enabled: Bool = false,
        stereo: Bool = true,
        barCount: Int = 64,
        barColor: ColorStyle = .gradient(["#1E3A5F", "#4A9EFF"]),
        backgroundColor: ColorConfig? = nil,
        barWidthRatio: Double = 0.7,
        minDb: Double = -60,
        maxDb: Double = 0,
        scale: SpectrumScale = .linear,
        noiseReduction: Double = 0.77,
        fftSize: Int = 1024,
        placement: SpectrumPlacement = .bottom,
        heightRatio: Double = 0.25
    ) {
        self.enabled = enabled
        self.stereo = stereo
        self.barCount = barCount
        self.barColor = barColor
        self.backgroundColor = backgroundColor
        self.barWidthRatio = barWidthRatio
        self.minDb = minDb
        self.maxDb = maxDb
        self.scale = scale
        self.noiseReduction = noiseReduction
        self.fftSize = fftSize
        self.placement = placement
        self.heightRatio = heightRatio
    }
}

extension SpectrumStyle: Sendable {}
