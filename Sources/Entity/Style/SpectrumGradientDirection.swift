/// How a multi-color `bar_color` gradient is mapped onto the bars (#297).
///
/// Only meaningful when `bar_color` carries two or more colors; a solid
/// `bar_color` renders identically under every mode. Mirrors lyra's text
/// color config in that the palette itself is the same `ColorStyle` — this
/// only chooses the axis the palette runs along.
///
/// - `frequency`: the gradient runs horizontally across the bar row, so the
///   color tracks the band (low frequencies one end, high the other).
/// - `amplitude`: the gradient runs vertically over the bar area, VU-meter
///   style — a bar shows the low colors near its base and reaches the high
///   colors only as it grows tall.
/// - `level`: each bar is a single flat color, picked from the gradient by
///   that bar's own height — a quiet bar is entirely the low color, a loud
///   one entirely the high color.
public enum SpectrumGradientDirection: String, CaseIterable {
    case frequency
    case amplitude
    case level
}

extension SpectrumGradientDirection: Codable {}
extension SpectrumGradientDirection: Sendable {}
