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

    @Option(
        name: .shortAndLong,
        help: "Scenarios to run (comma-separated: \(BenchmarkScenario.allCases.map(\.rawValue).joined(separator: ", ")))"
    )
    var scenarios: String = ""

    @Flag(help: "Output results as JSON")
    var json: Bool = false

    func run() async throws {
        @Dependency(\.benchmarkHandler) var handler
        @Dependency(\.standardOutput) var output

        let selected = parsedScenarios

        if json {
            var entries: [BenchmarkEntry] = []
            for await case .completed(let entry) in handler.run(scenarios: selected, duration: Double(duration)) {
                entries.append(entry)
            }
            output.writeJson(entries)
        } else {
            output.suppressEcho()
            defer { output.restoreEcho() }
            output.writeBenchmarkHeader()
            for await update in handler.run(scenarios: selected, duration: Double(duration)) {
                switch update {
                case .live(let entry): output.writeBenchmarkLive(entry)
                case .completed(let entry): output.writeBenchmarkResult(entry)
                }
            }
        }
    }

    private var parsedScenarios: [BenchmarkScenario] {
        guard !scenarios.isEmpty else { return [] }
        return scenarios.split(separator: ",")
            .compactMap { BenchmarkScenario(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }
}
