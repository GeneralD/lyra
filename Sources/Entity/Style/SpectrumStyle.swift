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
    public let barColor: ColorStyle
    /// Axis a multi-color `barColor` gradient runs along; ignored for solid.
    public let gradientDirection: SpectrumGradientDirection
    public let backgroundColor: ColorConfig?
    /// Bar thickness in points, fixed cava-style; the bar count is derived
    /// from the overlay width, not configured.
    public let barWidth: Double
    /// Gap between bars in points, fixed.
    public let barSpacing: Double
    /// Lowest / highest frequency shown, in Hz (cava's cut-offs).
    public let minFreq: Double
    public let maxFreq: Double
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
    /// Fraction of the overlay the bars may occupy along their growth axis,
    /// 0–1: the overlay height for `bottom`/`top`, the width for `left`/`right`.
    public let heightRatio: Double
    /// Optional absolute clamp (points) on the growth-axis extent, applied
    /// after `heightRatio` (CSS `min-height`/`max-height` semantics; min wins
    /// on conflict). `nil` disables that bound. Lets a ratio-based bar keep a
    /// sane length across wildly different displays — e.g. an ultrawide, where
    /// a pure ratio would stretch a horizontal placement across the screen.
    public let minHeight: Double?
    public let maxHeight: Double?
    /// Master opacity of the whole bar layer, 0…1, multiplied on top of
    /// `barColor`'s own alpha (see `SpectrumConfig.barOpacity`).
    public let barOpacity: Double
    /// Explicit bar corner radius in points, or `nil` to derive it from the
    /// bar thickness (`autoCornerRadius`). Per-bar it is capped at half the
    /// thickness at render time.
    public let barCornerRadius: Double?

    public init(
        enabled: Bool = false,
        stereo: Bool = true,
        barColor: ColorStyle = .gradient([
            "#060912B3", "#20407FB3", "#3E86F0B3", "#9C6CEEB3", "#F4F1FFB3",
        ]),
        gradientDirection: SpectrumGradientDirection = .level,
        backgroundColor: ColorConfig? = nil,
        barWidth: Double = 6,
        barSpacing: Double = 4,
        minFreq: Double = 40,
        maxFreq: Double = 14000,
        minDb: Double = -60,
        maxDb: Double = 0,
        scale: SpectrumScale = .linear,
        noiseReduction: Double = 0.77,
        fftSize: Int = 1024,
        placement: SpectrumPlacement = .bottom,
        heightRatio: Double = 0.25,
        minHeight: Double? = nil,
        maxHeight: Double? = nil,
        barOpacity: Double = 1,
        barCornerRadius: Double? = nil
    ) {
        self.enabled = enabled
        self.stereo = stereo
        self.barColor = barColor
        self.gradientDirection = gradientDirection
        self.backgroundColor = backgroundColor
        self.barWidth = barWidth
        self.barSpacing = barSpacing
        self.minFreq = minFreq
        self.maxFreq = maxFreq
        self.minDb = minDb
        self.maxDb = maxDb
        self.scale = scale
        self.noiseReduction = noiseReduction
        self.fftSize = fftSize
        self.placement = placement
        self.heightRatio = heightRatio
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.barOpacity = barOpacity
        self.barCornerRadius = barCornerRadius
    }
}

extension SpectrumStyle: Sendable {}
extension SpectrumStyle: Equatable {}
