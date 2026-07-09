import CoreAudio

/// Extracts the sample rate from an `AudioStreamBasicDescription`, returning
/// it when positive and `nil` otherwise. Pulling this decision out of the
/// CoreAudio call site makes it unit-testable without a live tap object.
func tapSampleRate(from format: AudioStreamBasicDescription) -> Double? {
    format.mSampleRate > 0 ? format.mSampleRate : nil
}

/// The sample rate to run the analyzer at, given the tap's freshly-read format:
/// its positive rate, or the 48 kHz mixdown default when the format is missing
/// (unreadable read) or malformed (non-positive rate). Pure — the live read is
/// the caller's job — so the fallback decision is tested without a live tap.
func resolvedTapSampleRate(from format: AudioStreamBasicDescription?) -> Double {
    format.flatMap(tapSampleRate(from:)) ?? 48000
}
