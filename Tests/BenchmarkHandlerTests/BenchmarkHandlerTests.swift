import Dependencies
import Domain
import Foundation
import Testing

@testable import BenchmarkHandler

// MARK: - Test Doubles

private final class MockGateway: ProcessGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [ResourceSnapshot]
    private var index = 0

    init(snapshots: [ResourceSnapshot]) {
        self.snapshots = snapshots
    }

    var resourceSnapshot: ResourceSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let snap = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return snap
    }

    // Unused stubs
    var overlayPIDs: [Int32] { [] }
    func spawnDaemon(executablePath: String) -> Int32? { nil }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { false }
    func isRunning(_ pid: Int32) -> Bool { false }
    func acquireLock() -> Bool { false }
    var isLocked: Bool { false }
    func releaseLock() {}
    func runLaunchctl(_ arguments: [String]) -> Int32 { 0 }
    func findExecutable(_ name: String) -> String? { nil }
    func run(executable: String, arguments: [String]) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}

private let baseline = ResourceSnapshot(cpuUser: 1.0, cpuSystem: 0.5, peakRSS: 1000, currentRSS: 800)
private let afterIdle = ResourceSnapshot(cpuUser: 1.01, cpuSystem: 0.51, peakRSS: 1000, currentRSS: 810)
private let afterSpike = ResourceSnapshot(cpuUser: 5.0, cpuSystem: 1.0, peakRSS: 1200, currentRSS: 900)

// MARK: - measure() tests

@Suite("BenchmarkHandlerImpl measure()")
struct MeasureTests {
    @Test("returns correct CPU delta between baseline and final snapshot")
    func cpuDelta() async throws {
        let gateway = MockGateway(snapshots: [baseline, afterIdle])
        let entries = await withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.processGateway = gateway
        } operation: {
            await BenchmarkHandlerImpl().measure(scenarios: [.idle], duration: 1)
        }

        let entry = try #require(entries.first)
        #expect(entry.scenario == .idle)
        #expect(entry.cpuUserSeconds > 0)
        #expect(entry.cpuSystemSeconds > 0)
    }

    @Test("empty scenarios defaults to all cases")
    func emptyScenariosDefaultsToAll() async {
        let snap = ResourceSnapshot(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0)
        let gateway = MockGateway(snapshots: [snap])
        let entries = await withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.processGateway = gateway
        } operation: {
            await BenchmarkHandlerImpl().measure(scenarios: [], duration: 1)
        }

        #expect(entries.count == BenchmarkScenario.allCases.count)
    }

    @Test("RSS values come from sampler snapshot")
    func rssFromSampler() async throws {
        let gateway = MockGateway(snapshots: [baseline, afterSpike])
        let entries = await withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.processGateway = gateway
        } operation: {
            await BenchmarkHandlerImpl().measure(scenarios: [.cpuSpike], duration: 1)
        }

        let entry = try #require(entries.first)
        #expect(entry.peakRSSBytes == afterSpike.peakRSS)
        #expect(entry.currentRSSBytes == afterSpike.currentRSS)
    }
}

// MARK: - run() stream tests

@Suite("BenchmarkHandlerImpl run()")
struct RunTests {
    @Test("emits header first")
    func headerFirst() async {
        let snap = ResourceSnapshot(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0)
        let gateway = MockGateway(snapshots: [snap])
        var first: BenchmarkUpdate?

        await withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.processGateway = gateway
        } operation: {
            for await update in BenchmarkHandlerImpl().run(scenarios: [.idle], duration: 1) {
                first = update
                break
            }
        }

        guard case .header = first else {
            Issue.record("Expected .header as first update")
            return
        }
    }

    @Test("emits completed for each scenario")
    func completedPerScenario() async {
        let snap = ResourceSnapshot(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0)
        let gateway = MockGateway(snapshots: [snap])
        var completedCount = 0

        await withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.processGateway = gateway
        } operation: {
            for await case .completed in BenchmarkHandlerImpl().run(scenarios: [.idle, .cpuSpike], duration: 1) {
                completedCount += 1
            }
        }

        #expect(completedCount == 2)
    }

    @Test("completed entry has correct CPU delta from sampler")
    func completedCpuDelta() async throws {
        let gateway = MockGateway(snapshots: [baseline, afterIdle, afterIdle])
        var completed: BenchmarkEntry?

        await withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.processGateway = gateway
        } operation: {
            for await case .completed(let entry) in BenchmarkHandlerImpl().run(scenarios: [.idle], duration: 1) {
                completed = entry
            }
        }

        let entry = try #require(completed)
        #expect(entry.scenario == .idle)
        #expect(entry.cpuUserSeconds == afterIdle.cpuUser - baseline.cpuUser)
    }
}

// MARK: - BenchmarkEntry encoding

@Suite("BenchmarkEntry")
struct EntryTests {
    @Test("encodes to JSON with scenario rawValue")
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
}
