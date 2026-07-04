/// Where the spectrum analyzer bars sit inside the overlay (#23). `bottom`
/// and `top` grow the bars vertically from that edge; `left` and `right`
/// rotate them into horizontal columns growing inward from that edge (#297).
public enum SpectrumPlacement: String, CaseIterable {
    /// Anchored to the bottom edge, occupying `heightRatio` of the overlay.
    case bottom
    /// Anchored to the top edge, bars growing downward.
    case top
    /// Anchored to the left edge, bars rotated horizontal and growing right,
    /// the strip occupying `heightRatio` of the overlay width.
    case left
    /// Anchored to the right edge, bars rotated horizontal and growing left.
    case right
    /// Bottom-anchored like `bottom`, but allowed the full overlay height so
    /// the bars form a subtle backdrop behind the lyrics.
    case underlay
}

extension SpectrumPlacement: Sendable {}
extension SpectrumPlacement: Codable {}
