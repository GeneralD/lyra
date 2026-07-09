import CoreAudio
import Testing

@testable import AudioTapDataSource

@Suite("tapSampleRate")
struct TapSampleRateTests {
    private func format(rate: Double) -> AudioStreamBasicDescription {
        var f = AudioStreamBasicDescription()
        f.mSampleRate = rate
        return f
    }

    @Test("positive rate is returned as-is — 44.1 kHz")
    func rate44100() {
        #expect(tapSampleRate(from: format(rate: 44100)) == 44100)
    }

    @Test("positive rate is returned as-is — 48 kHz")
    func rate48000() {
        #expect(tapSampleRate(from: format(rate: 48000)) == 48000)
    }

    @Test("zero rate yields nil — no audio stream")
    func zeroYieldsNil() {
        #expect(tapSampleRate(from: format(rate: 0)) == nil)
    }

    @Test("negative rate yields nil — malformed descriptor")
    func negativeYieldsNil() {
        #expect(tapSampleRate(from: format(rate: -1)) == nil)
    }
}

@Suite("resolvedTapSampleRate")
struct ResolvedTapSampleRateTests {
    private func format(rate: Double) -> AudioStreamBasicDescription {
        var f = AudioStreamBasicDescription()
        f.mSampleRate = rate
        return f
    }

    @Test("a readable positive rate is used as-is")
    func usesPositiveRate() {
        #expect(resolvedTapSampleRate(from: format(rate: 44100)) == 44100)
    }

    @Test("an unreadable format falls back to the 48 kHz mixdown default")
    func unreadableFallsBackTo48k() {
        #expect(resolvedTapSampleRate(from: nil) == 48000)
    }

    @Test("a malformed (non-positive) rate falls back to 48 kHz")
    func malformedFallsBackTo48k() {
        #expect(resolvedTapSampleRate(from: format(rate: 0)) == 48000)
        #expect(resolvedTapSampleRate(from: format(rate: -1)) == 48000)
    }
}
