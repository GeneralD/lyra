/// One stereo PCM window captured from the process tap (#297): matching
/// left/right channel samples, oldest first. Both sides are empty while no
/// capture is active or before the capture buffer has filled once.
public struct StereoSamples {
    public let left: [Float]
    public let right: [Float]

    public init(left: [Float] = [], right: [Float] = []) {
        self.left = left
        self.right = right
    }
}

extension StereoSamples: Sendable {}
extension StereoSamples: Equatable {}
