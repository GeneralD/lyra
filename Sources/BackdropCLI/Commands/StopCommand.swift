import ArgumentParser

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the running overlay"
    )

    func run() {
        print(ProcessManager.stopExisting() ? "Stopped" : "Not running")
    }
}
