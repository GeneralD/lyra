/// Configuration for the spectrum analyzer overlay (#23), decoded from the
/// `[spectrum]` TOML section. Every field is optional in TOML; omitting the
/// section entirely is equivalent to `enabled = false`.
public struct SpectrumConfig {
    public let enabled: Bool
    /// Splits the bar row into the two capture channels, cava-style: the
    /// left channel mirrored on the left half, the right channel on the
    /// right half, lowest frequencies meeting in the center. `false`
    /// averages both channels into one mono row.
    public let stereo: Bool
    public let barColor: ColorStyle
    /// Axis a multi-color `bar_color` gradient runs along (`frequency` /
    /// `amplitude` / `level`); ignored for a solid color.
    public let gradientDirection: SpectrumGradientDirection
    public let backgroundColor: ColorConfig?
    /// Bar thickness in points, fixed (cava-style). The number of bars is
    /// derived from the overlay width, not configured.
    public let barWidth: FlexibleDouble
    /// Gap between bars in points, fixed.
    public let barSpacing: FlexibleDouble
    /// Lowest frequency shown, in Hz (cava's `low_cut_off`).
    public let minFreq: FlexibleDouble
    /// Highest frequency shown, in Hz (cava's `high_cut_off`).
    public let maxFreq: FlexibleDouble
    public let minDb: FlexibleDouble
    public let maxDb: FlexibleDouble
    /// Height scale of the bars: `linear` (cava's look — quiet bands stay
    /// low, loud ones tower) or `db` (flatter, decibels map to height).
    public let scale: SpectrumScale
    /// Motion smoothing 0–100 (cava's `noise_reduction`): the leaky-integral
    /// memory of the bar filter and the gravity scaling of the release. 0 is
    /// jumpy and instant, 100 glacially smooth.
    public let noiseReduction: FlexibleDouble
    public let fftSize: FlexibleDouble
    public let placement: SpectrumPlacement
    /// Fraction of the overlay the bars may occupy along their growth axis, 0–1.
    public let heightRatio: FlexibleDouble
    /// Optional absolute clamp (points) on the growth-axis extent, applied on
    /// top of `heightRatio` (like CSS `min-height`/`max-height`). Omitting a
    /// bound leaves it unclamped. Useful to cap a ratio-based length on a very
    /// wide display (e.g. an ultrawide, where a horizontal placement would
    /// otherwise stretch across the screen).
    public let minHeight: FlexibleDouble?
    public let maxHeight: FlexibleDouble?
    /// Master opacity of the whole bar layer, 0–1, multiplied on top of
    /// `bar_color`'s own alpha. Setting an opaque `bar_color` and driving
    /// transparency here separates colour from opacity; the two also compose.
    /// Independent of `background_color`.
    public let barOpacity: FlexibleDouble
    /// Corner radius of the bars, in points. `nil` derives it from `bar_width`
    /// (cava-style `min(bar_width / 4, 3)`); an explicit value overrides that,
    /// `0` for square corners. Per-bar the radius is capped at half the bar
    /// thickness.
    public let barCornerRadius: FlexibleDouble?
}

extension SpectrumConfig: Sendable {}

extension SpectrumConfig {
    static let defaults = SpectrumConfig(
        enabled: false,
        stereo: true,
        barColor: .gradient(["#060912B3", "#20407FB3", "#3E86F0B3", "#9C6CEEB3", "#F4F1FFB3"]),
        gradientDirection: .level,
        backgroundColor: nil,
        barWidth: 6,
        barSpacing: 4,
        minFreq: 40,
        maxFreq: 14000,
        minDb: -60,
        maxDb: 0,
        scale: .linear,
        noiseReduction: 77,
        fftSize: 1024,
        placement: .bottom,
        heightRatio: 0.25,
        minHeight: nil,
        maxHeight: nil,
        barOpacity: 1,
        barCornerRadius: nil
    )
}

extension SpectrumConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case enabled
        case stereo
        case barColor = "bar_color"
        case gradientDirection = "gradient_direction"
        case backgroundColor = "background_color"
        case barWidth = "bar_width"
        case barSpacing = "bar_spacing"
        case minFreq = "min_freq"
        case maxFreq = "max_freq"
        case minDb = "min_db"
        case maxDb = "max_db"
        case scale
        case noiseReduction = "noise_reduction"
        case fftSize = "fft_size"
        case placement
        case heightRatio = "height_ratio"
        case minHeight = "min_height"
        case maxHeight = "max_height"
        case barOpacity = "bar_opacity"
        case barCornerRadius = "bar_corner_radius"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.defaults.enabled
        stereo = try c.decodeIfPresent(Bool.self, forKey: .stereo) ?? Self.defaults.stereo
        barColor = try c.decodeIfPresent(ColorStyle.self, forKey: .barColor) ?? Self.defaults.barColor
        gradientDirection = try c.decodeIfPresent(SpectrumGradientDirection.self, forKey: .gradientDirection) ?? Self.defaults.gradientDirection
        backgroundColor = try c.decodeIfPresent(ColorConfig.self, forKey: .backgroundColor) ?? Self.defaults.backgroundColor
        barWidth = try c.decodeIfPresent(FlexibleDouble.self, forKey: .barWidth) ?? Self.defaults.barWidth
        barSpacing = try c.decodeIfPresent(FlexibleDouble.self, forKey: .barSpacing) ?? Self.defaults.barSpacing
        minFreq = try c.decodeIfPresent(FlexibleDouble.self, forKey: .minFreq) ?? Self.defaults.minFreq
        maxFreq = try c.decodeIfPresent(FlexibleDouble.self, forKey: .maxFreq) ?? Self.defaults.maxFreq
        minDb = try c.decodeIfPresent(FlexibleDouble.self, forKey: .minDb) ?? Self.defaults.minDb
        maxDb = try c.decodeIfPresent(FlexibleDouble.self, forKey: .maxDb) ?? Self.defaults.maxDb
        scale = try c.decodeIfPresent(SpectrumScale.self, forKey: .scale) ?? Self.defaults.scale
        noiseReduction = try c.decodeIfPresent(FlexibleDouble.self, forKey: .noiseReduction) ?? Self.defaults.noiseReduction
        fftSize = try c.decodeIfPresent(FlexibleDouble.self, forKey: .fftSize) ?? Self.defaults.fftSize
        placement = try c.decodeIfPresent(SpectrumPlacement.self, forKey: .placement) ?? Self.defaults.placement
        heightRatio = try c.decodeIfPresent(FlexibleDouble.self, forKey: .heightRatio) ?? Self.defaults.heightRatio
        minHeight = try c.decodeIfPresent(FlexibleDouble.self, forKey: .minHeight)
        maxHeight = try c.decodeIfPresent(FlexibleDouble.self, forKey: .maxHeight)
        barOpacity = try c.decodeIfPresent(FlexibleDouble.self, forKey: .barOpacity) ?? Self.defaults.barOpacity
        barCornerRadius = try c.decodeIfPresent(FlexibleDouble.self, forKey: .barCornerRadius)
    }
}
