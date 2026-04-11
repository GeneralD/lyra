import Dependencies
import Domain
import Foundation

public struct BenchmarkHandlerImpl {
    public init() {}

    @Dependency(\.continuousClock) private var clock
    @Dependency(\.processGateway) private var gateway
}

extension BenchmarkHandlerImpl: BenchmarkHandler {
    public func run(scenarios: [BenchmarkScenario], duration: Double) -> AsyncStream<BenchmarkUpdate> {
        let selected = scenarios.isEmpty ? BenchmarkScenario.allCases : scenarios
        return AsyncStream { continuation in
            let task = Task {
                continuation.yield(.header)
                for scenario in selected {
                    guard !Task.isCancelled else { break }
                    await measureWithLiveUpdates(
                        scenario: scenario, duration: duration, continuation: continuation)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func measure(scenarios: [BenchmarkScenario], duration: Double) async -> [BenchmarkEntry] {
        let selected = scenarios.isEmpty ? BenchmarkScenario.allCases : scenarios
        return await selected.asyncMap { scenario in
            let baseline = gateway.resourceSnapshot
            let elapsed = await clock.measure {
                await runScenario(scenario, duration: duration)
            }
            return entry(scenario: scenario, elapsed: elapsed, baseline: baseline, current: gateway.resourceSnapshot)
        }
    }
}

extension BenchmarkHandlerImpl {
    private func measureWithLiveUpdates(
        scenario: BenchmarkScenario, duration: Double,
        continuation: AsyncStream<BenchmarkUpdate>.Continuation
    ) async {
        let baseline = gateway.resourceSnapshot

        let elapsed: Duration = await clock.measure {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await runScenario(scenario, duration: duration)
                }

                group.addTask { [gateway, clock] in
                    var accumulated: Duration = .zero
                    while !Task.isCancelled {
                        try? await clock.sleep(for: .milliseconds(250))
                        accumulated += .milliseconds(250)
                        guard !Task.isCancelled else { break }
                        continuation.yield(
                            .live(
                                entry(
                                    scenario: scenario, elapsed: accumulated, baseline: baseline,
                                    current: gateway.resourceSnapshot)))
                    }
                }

                // Wait for scenario to finish, then cancel live updater
                await group.next()
                group.cancelAll()
            }
        }

        continuation.yield(
            .completed(entry(scenario: scenario, elapsed: elapsed, baseline: baseline, current: gateway.resourceSnapshot)))
    }

    private func entry(
        scenario: BenchmarkScenario, elapsed: Duration, baseline: ResourceSnapshot,
        current: ResourceSnapshot
    ) -> BenchmarkEntry {
        BenchmarkEntry(
            scenario: scenario,
            durationSeconds: elapsed.fractionalSeconds,
            cpuUserSeconds: current.cpuUser - baseline.cpuUser,
            cpuSystemSeconds: current.cpuSystem - baseline.cpuSystem,
            peakRSSBytes: current.peakRSS,
            currentRSSBytes: current.currentRSS
        )
    }

    private func runScenario(_ scenario: BenchmarkScenario, duration: Double) async {
        switch scenario {
        case .idle:
            try? await clock.sleep(for: .seconds(duration))

        case .cpuSpike:
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [clock] in
                    try? await clock.sleep(for: .seconds(duration))
                }
                for _ in 0..<ProcessInfo.processInfo.processorCount {
                    group.addTask {
                        while !Task.isCancelled {
                            _ = (0..<1000).reduce(0.0) { acc, i in acc + sin(Double(i)) }
                            await Task.yield()
                        }
                    }
                }
                await group.next()
                group.cancelAll()
            }

        case .memoryAlloc:
            var buffers: [Data] = []
            let chunkSize = 1_048_576
            let iterations = max(1, Int(duration / 0.1))
            for _ in 0..<iterations {
                guard !Task.isCancelled else { break }
                buffers.append(Data(repeating: 0xAB, count: chunkSize))
                try? await clock.sleep(for: .milliseconds(100))
            }
            _ = buffers.count
        }
    }
}

extension Duration {
    fileprivate var fractionalSeconds: Double {
        let (s, a) = components
        return Double(s) + Double(a) / 1_000_000_000_000_000_000
    }
}

extension Array {
    fileprivate func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            results.append(await transform(element))
        }
        return results
    }
}
