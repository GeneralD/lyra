import Darwin
import Domain
import Foundation

public struct BenchmarkHandlerImpl {
    public init() {}
}

extension BenchmarkHandlerImpl: BenchmarkHandler {
    public var availableScenarios: [String] {
        ["idle", "cpu_spike", "memory_alloc"]
    }

    public func measure(scenario: String, duration: Double) async -> BenchmarkEntry {
        let before = ProcessSnapshot.current
        let start = ContinuousClock.now

        await runScenario(scenario, duration: duration)

        let elapsed = start.duration(to: .now)
        let after = ProcessSnapshot.current

        return BenchmarkEntry(
            scenario: scenario,
            durationSeconds: elapsed.seconds,
            cpuUserSeconds: after.cpuUser - before.cpuUser,
            cpuSystemSeconds: after.cpuSystem - before.cpuSystem,
            peakRSSBytes: after.peakRSS,
            currentRSSBytes: after.currentRSS
        )
    }
}

extension BenchmarkHandlerImpl {
    private func runScenario(_ scenario: String, duration: Double) async {
        switch scenario {
        case "idle":
            try? await Task.sleep(for: .seconds(duration))

        case "cpu_spike":
            await withTaskGroup(of: Void.self) { group in
                let deadline = ContinuousClock.now + .seconds(duration)
                for _ in 0..<ProcessInfo.processInfo.processorCount {
                    group.addTask {
                        while ContinuousClock.now < deadline {
                            _ = (0..<1000).reduce(0.0) { acc, i in acc + sin(Double(i)) }
                            await Task.yield()
                        }
                    }
                }
            }

        case "memory_alloc":
            var buffers: [Data] = []
            let chunkSize = 1_048_576
            let deadline = ContinuousClock.now + .seconds(duration)
            while ContinuousClock.now < deadline {
                buffers.append(Data(repeating: 0xAB, count: chunkSize))
                try? await Task.sleep(for: .milliseconds(100))
            }
            _ = buffers.count

        default:
            break
        }
    }
}

private struct ProcessSnapshot {
    let cpuUser: Double
    let cpuSystem: Double
    let peakRSS: Int64
    let currentRSS: Int64

    static var current: ProcessSnapshot {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                _ = task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }

        return ProcessSnapshot(
            cpuUser: usage.ru_utime.seconds,
            cpuSystem: usage.ru_stime.seconds,
            peakRSS: Int64(usage.ru_maxrss),
            currentRSS: Int64(info.resident_size)
        )
    }
}

extension timeval {
    fileprivate var seconds: Double {
        Double(tv_sec) + Double(tv_usec) / 1_000_000
    }
}

extension Duration {
    fileprivate var seconds: Double {
        let (s, a) = components
        return Double(s) + Double(a) / 1_000_000_000_000_000_000
    }
}
