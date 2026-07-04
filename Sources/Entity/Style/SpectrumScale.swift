/// Height scale of the spectrum bars (#297).
///
/// `linear` is cava's look: bar height tracks amplitude directly, so a bar
/// 30 dB under the peak draws at ~3% — quiet bands stay low and the loud
/// ones tower. `db` maps decibels linearly into height, which compresses
/// the same 30 dB gap into half height — a flatter, carpet-like row.
public enum SpectrumScale: String, CaseIterable {
    case linear
    case db
}

extension SpectrumScale: Codable {}
extension SpectrumScale: Sendable {}
