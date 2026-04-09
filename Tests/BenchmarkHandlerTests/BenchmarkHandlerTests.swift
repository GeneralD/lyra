import Entity
import Foundation
import Testing

@testable import BenchmarkHandler

@Suite("BenchmarkHandlerImpl")
struct BenchmarkHandlerTests {
    @Test("idle scenario returns non-negative CPU and memory values")
    func idleScenario() async {
        let handler = BenchmarkHandlerImpl()
        let entry = await handler.measure(scenario: "idle", duration: 1)

        #expect(entry.scenario == "idle")
        #expect(entry.durationSeconds >= 1.0)
        #expect(entry.cpuUserSeconds >= 0)
        #expect(entry.cpuSystemSeconds >= 0)
        #expect(entry.currentRSSBytes > 0)
        #expect(entry.peakRSSBytes > 0)
    }

    @Test("cpu_spike scenario shows higher CPU than idle")
    func cpuSpikeHigherThanIdle() async {
        let handler = BenchmarkHandlerImpl()
        let idle = await handler.measure(scenario: "idle", duration: 1)
        let spike = await handler.measure(scenario: "cpu_spike", duration: 1)
        #expect(spike.cpuUserSeconds > idle.cpuUserSeconds)
    }

    @Test("BenchmarkEntry encodes to JSON")
    func entryEncodesToJson() throws {
        let entry = BenchmarkEntry(
            scenario: "test",
            durationSeconds: 1.0,
            cpuUserSeconds: 0.5,
            cpuSystemSeconds: 0.1,
            peakRSSBytes: 1024,
            currentRSSBytes: 512
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(BenchmarkEntry.self, from: data)
        #expect(decoded.scenario == "test")
        #expect(decoded.durationSeconds == 1.0)
    }

    @Test("availableScenarios returns three scenarios")
    func availableScenarios() {
        let handler = BenchmarkHandlerImpl()
        #expect(handler.availableScenarios.count == 3)
        #expect(handler.availableScenarios.contains("idle"))
        #expect(handler.availableScenarios.contains("cpu_spike"))
        #expect(handler.availableScenarios.contains("memory_alloc"))
    }
}
