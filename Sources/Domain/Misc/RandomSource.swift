import Dependencies

public protocol RandomSource: Sendable {
    /// Returns an integer in the range `0..<count`. Caller guarantees `count > 0`.
    func next(below count: Int) -> Int
}

public enum RandomSourceKey: TestDependencyKey {
    public static let testValue: any RandomSource = SystemRandomSource()
}

extension DependencyValues {
    public var randomSource: any RandomSource {
        get { self[RandomSourceKey.self] }
        set { self[RandomSourceKey.self] = newValue }
    }
}

public struct SystemRandomSource: RandomSource {
    public init() {}
    public func next(below count: Int) -> Int {
        Int.random(in: 0..<count)
    }
}
