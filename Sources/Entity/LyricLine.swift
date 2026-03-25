import Foundation

public struct LyricLine {
    public let time: TimeInterval
    public let text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

extension LyricLine: Sendable {}
extension LyricLine: Equatable {}
