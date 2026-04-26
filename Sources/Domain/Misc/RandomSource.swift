import Dependencies

public protocol RandomSource: Sendable {
    /// Returns an integer in the range `0..<count`. Caller guarantees `count > 0`.
    func next(below count: Int) -> Int
}

public enum RandomSourceKey: TestDependencyKey {
    /// Deterministic stub: always returns 0. Tests that depend on randomness must
    /// override via `withDependencies { $0.randomSource = ... }`.
    public static let testValue: any RandomSource = ZeroRandomSource()
}

extension DependencyValues {
    public var randomSource: any RandomSource {
        get { self[RandomSourceKey.self] }
        set { self[RandomSourceKey.self] = newValue }
    }
}

private struct ZeroRandomSource: RandomSource {
    func next(below count: Int) -> Int { 0 }
}
