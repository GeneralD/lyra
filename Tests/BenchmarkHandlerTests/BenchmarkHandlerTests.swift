import Entity
import Foundation
import Testing

@testable import BenchmarkHandler

@Suite("BenchmarkHandlerImpl")
struct BenchmarkHandlerTests {
    @Test("idle scenario emits live updates then completed")
    func idleScenario() async {
        let handler = BenchmarkHandlerImpl()
        var liveCount = 0
        var completed: BenchmarkEntry?

        for await update in handler.run(scenarios: [.idle], duration: 1) {
            switch update {
            case .live: liveCount += 1
            case .completed(let entry): completed = entry
            }
        }

        let entry = try! #require(completed)
        #expect(entry.scenario == .idle)
        #expect(entry.durationSeconds >= 1.0)
        #expect(entry.cpuUserSeconds >= 0)
        #expect(entry.currentRSSBytes > 0)
        #expect(liveCount >= 1)
    }

    @Test("cpu_spike scenario shows higher CPU than idle")
    func cpuSpikeHigherThanIdle() async {
        let handler = BenchmarkHandlerImpl()
        var results: [BenchmarkEntry] = []

        for await case .completed(let entry) in handler.run(scenarios: [.idle, .cpuSpike], duration: 1) {
            results.append(entry)
        }

        #expect(results.count == 2)
        #expect(results[1].cpuUserSeconds > results[0].cpuUserSeconds)
    }

    @Test("BenchmarkEntry encodes to JSON with scenario rawValue")
    func entryEncodesToJson() throws {
        let entry = BenchmarkEntry(
            scenario: .idle,
            durationSeconds: 1.0,
            cpuUserSeconds: 0.5,
            cpuSystemSeconds: 0.1,
            peakRSSBytes: 1024,
            currentRSSBytes: 512
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(BenchmarkEntry.self, from: data)
        #expect(decoded.scenario == .idle)
        #expect(decoded.durationSeconds == 1.0)
    }

    @Test("empty scenarios defaults to all cases")
    func emptyScenariosDefaultsToAll() async {
        let handler = BenchmarkHandlerImpl()
        var completedCount = 0

        for await case .completed in handler.run(scenarios: [], duration: 1) {
            completedCount += 1
        }

        #expect(completedCount == BenchmarkScenario.allCases.count)
    }
}
