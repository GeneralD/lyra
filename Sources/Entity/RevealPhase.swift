/// Payload-less lifecycle of a decode-reveal text animation.
///
/// Presenters expose this instead of `FetchState<String>` so the public API
/// carries only the animation lifecycle, never the target string — the View
/// already reads the rendered text from `displayTitle` / `displayArtist`, and
/// the decode target belongs in a private field, not the public surface (#275).
public enum RevealPhase {
    /// No content — the field is empty and should not be rendered.
    case idle
    /// Decode animation is in progress.
    case revealing
    /// Decode animation has settled on the final text.
    case revealed
}

extension RevealPhase: Sendable {}
extension RevealPhase: Equatable {}
