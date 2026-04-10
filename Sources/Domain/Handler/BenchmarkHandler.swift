import Dependencies

public protocol BenchmarkHandler: Sendable {
    func run(scenarios: [BenchmarkScenario], duration: Double) -> AsyncStream<BenchmarkUpdate>
    func measure(scenarios: [BenchmarkScenario], duration: Double) async -> [BenchmarkEntry]
}

public enum BenchmarkHandlerKey: TestDependencyKey {
    public static let testValue: any BenchmarkHandler = UnimplementedBenchmarkHandler()
}

extension DependencyValues {
    public var benchmarkHandler: any BenchmarkHandler {
        get { self[BenchmarkHandlerKey.self] }
        set { self[BenchmarkHandlerKey.self] = newValue }
    }
}

private struct UnimplementedBenchmarkHandler: BenchmarkHandler {
    func run(scenarios: [BenchmarkScenario], duration: Double) -> AsyncStream<BenchmarkUpdate> {
        AsyncStream { $0.finish() }
    }
    func measure(scenarios: [BenchmarkScenario], duration: Double) async -> [BenchmarkEntry] { [] }
}
