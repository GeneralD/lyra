/// Where the spectrum analyzer bars sit inside the overlay (#23).
public enum SpectrumPlacement: String, CaseIterable {
    /// Anchored to the bottom edge, occupying `heightRatio` of the overlay.
    case bottom
    /// Anchored to the top edge, bars growing downward.
    case top
    /// Bottom-anchored like `bottom`, but allowed the full overlay height so
    /// the bars form a subtle backdrop behind the lyrics.
    case underlay
}

extension SpectrumPlacement: Sendable {}
extension SpectrumPlacement: Codable {}
