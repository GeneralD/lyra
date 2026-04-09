import ArgumentParser
import AsyncRunnableCommand
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
            output.writeBenchmarkHeader()
            for scenario in selected {
                output.write("  \(scenario)...")
                let entry = await handler.measure(scenario: scenario, duration: Double(duration))
                output.write(entry)
            }
        }
    }
}
