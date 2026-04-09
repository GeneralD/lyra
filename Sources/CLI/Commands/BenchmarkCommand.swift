import ArgumentParser
import AsyncRunnableCommand
import Darwin
import Dependencies
import Domain

struct BenchmarkCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Measure CPU, memory, and energy baselines"
    )

    @Option(name: .shortAndLong, help: "Duration per scenario in seconds")
    var duration: Int = 5

    @Option(name: .shortAndLong, help: "Scenarios to run (comma-separated: idle, cpu_spike, memory_alloc)")
    var scenarios: String = "idle,cpu_spike,memory_alloc"

    @Flag(help: "Output results as JSON")
    var json: Bool = false

    func run() async throws {
        @Dependency(\.benchmarkHandler) var handler
        @Dependency(\.standardOutput) var output

        let requested = scenarios.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let available = handler.availableScenarios
        let selected = requested.isEmpty ? available : requested.filter { available.contains($0) }

        guard !selected.isEmpty else {
            output.writeError("No valid scenarios. Available: \(available.joined(separator: ", "))")
            throw ExitCode.failure
        }

        if json {
            var entries: [BenchmarkEntry] = []
            for scenario in selected {
                let entry = await handler.measure(scenario: scenario, duration: Double(duration))
                entries.append(entry)
            }
            output.writeJson(entries)
        } else {
            let restore = suppressEcho()
            defer { restore() }

            output.writeBenchmarkHeader()
            for scenario in selected {
                let entry = await measureWithLiveDisplay(
                    handler: handler, output: output, scenario: scenario, duration: Double(duration))
                output.write(entry)
            }
        }
    }

    private func measureWithLiveDisplay(
        handler: any BenchmarkHandler, output: any StandardOutput, scenario: String, duration: Double
    ) async -> BenchmarkEntry {
        let baseline = handler.currentMetrics
        let start = ContinuousClock.now

        return await withTaskGroup(of: BenchmarkEntry?.self) { group in
            group.addTask {
                await handler.measure(scenario: scenario, duration: duration)
            }

            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { break }
                    let elapsed = Double(start.duration(to: .now).components.seconds)
                    output.writeBenchmarkLive(
                        scenario: scenario, elapsed: elapsed,
                        metrics: handler.currentMetrics, baseline: baseline)
                }
                return nil
            }

            var entry: BenchmarkEntry!
            for await result in group {
                guard let result else { continue }
                entry = result
                group.cancelAll()
                break
            }
            return entry
        }
    }

    private func suppressEcho() -> () -> Void {
        var old = termios()
        tcgetattr(STDIN_FILENO, &old)
        var raw = old
        raw.c_lflag &= ~UInt(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        return { tcsetattr(STDIN_FILENO, TCSANOW, &old) }
    }
}
