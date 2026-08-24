/// Where an error report came from, as it appears in the daemon's stderr line (#345).
///
/// The set is closed on purpose. Before this existed the subsystem was a bare string
/// baked into each `fputs` call, so nothing stopped the four sites from disagreeing —
/// and they did (`LRCLIB` / `MusicBrainz` / `AI` / `spectrum:`, mixing case and an
/// extra colon). A raw-value enum makes the vocabulary a compile-time fact and gives
/// the naming rule something to be tested against.
public enum ErrorSubsystem: String, Sendable, CaseIterable {
    /// The LRCLIB lyrics catalog.
    case lrclib = "LRCLIB"
    /// The MusicBrainz metadata catalog.
    case musicBrainz = "MusicBrainz"
    /// The user-configured OpenAI-compatible metadata extractor.
    case ai = "AI"
    /// Audio capture and analysis for the spectrum overlay.
    case spectrum = "Spectrum"
}
