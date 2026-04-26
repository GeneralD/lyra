import Domain

public struct SystemRandomSource: RandomSource {
    public init() {}
    public func next(below count: Int) -> Int {
        .random(in: 0..<count)
    }
}
