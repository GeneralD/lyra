/// One stereo PCM window captured from the process tap (#297): matching
/// left/right channel samples, oldest first, tagged with the tap's actual
/// sample rate (#299) so the analyzer maps Hz to FFT bins for the real
/// hardware rate rather than a fixed 48 kHz assumption. Both sides are empty
/// while no capture is active or before the capture buffer has filled once.
public struct StereoSamples {
    public let left: [Float]
    public let right: [Float]
    /// The tap's sample rate in Hz; 48000 as a placeholder when no capture is
    /// active (the analyzer never runs on an empty window).
    public let sampleRate: Double

    public init(left: [Float] = [], right: [Float] = [], sampleRate: Double = 48000) {
        self.left = left
        self.right = right
        self.sampleRate = sampleRate
    }
}

extension StereoSamples: Sendable {}
extension StereoSamples: Equatable {}
