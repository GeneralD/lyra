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
    public let barCount: FlexibleDouble
    public let barColor: ColorStyle
    public let backgroundColor: ColorConfig?
    /// Bar width as a fraction of one bar slot (bar + gap), 0–1.
    public let barWidthRatio: FlexibleDouble
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
    /// Fraction of the overlay height the bars may occupy, 0–1.
    public let heightRatio: FlexibleDouble
}

extension SpectrumConfig: Sendable {}

extension SpectrumConfig {
    static let defaults = SpectrumConfig(
        enabled: false,
        stereo: true,
        barCount: 64,
        barColor: .gradient(["#1E3A5F", "#4A9EFF"]),
        backgroundColor: nil,
        barWidthRatio: 0.7,
        minDb: -60,
        maxDb: 0,
        scale: .linear,
        noiseReduction: 77,
        fftSize: 1024,
        placement: .bottom,
        heightRatio: 0.25
    )
}

extension SpectrumConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case enabled
        case stereo
        case barCount = "bar_count"
        case barColor = "bar_color"
        case backgroundColor = "background_color"
        case barWidthRatio = "bar_width_ratio"
        case minDb = "min_db"
        case maxDb = "max_db"
        case scale
        case noiseReduction = "noise_reduction"
        case fftSize = "fft_size"
        case placement
        case heightRatio = "height_ratio"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.defaults.enabled
        stereo = try c.decodeIfPresent(Bool.self, forKey: .stereo) ?? Self.defaults.stereo
        barCount = try c.decodeIfPresent(FlexibleDouble.self, forKey: .barCount) ?? Self.defaults.barCount
        barColor = try c.decodeIfPresent(ColorStyle.self, forKey: .barColor) ?? Self.defaults.barColor
        backgroundColor = try c.decodeIfPresent(ColorConfig.self, forKey: .backgroundColor) ?? Self.defaults.backgroundColor
        barWidthRatio = try c.decodeIfPresent(FlexibleDouble.self, forKey: .barWidthRatio) ?? Self.defaults.barWidthRatio
        minDb = try c.decodeIfPresent(FlexibleDouble.self, forKey: .minDb) ?? Self.defaults.minDb
        maxDb = try c.decodeIfPresent(FlexibleDouble.self, forKey: .maxDb) ?? Self.defaults.maxDb
        scale = try c.decodeIfPresent(SpectrumScale.self, forKey: .scale) ?? Self.defaults.scale
        noiseReduction = try c.decodeIfPresent(FlexibleDouble.self, forKey: .noiseReduction) ?? Self.defaults.noiseReduction
        fftSize = try c.decodeIfPresent(FlexibleDouble.self, forKey: .fftSize) ?? Self.defaults.fftSize
        placement = try c.decodeIfPresent(SpectrumPlacement.self, forKey: .placement) ?? Self.defaults.placement
        heightRatio = try c.decodeIfPresent(FlexibleDouble.self, forKey: .heightRatio) ?? Self.defaults.heightRatio
    }
}
