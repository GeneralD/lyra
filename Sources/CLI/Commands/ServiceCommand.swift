import ArgumentParser
import Dependencies
import Domain

struct ServiceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Manage login item service",
        subcommands: [ServiceInstallCommand.self, ServiceUninstallCommand.self]
    )
}

private struct ServiceInstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Register as login item (LaunchAgent)"
    )

    func run() throws {
        @Dependency(\.processHandler) var processHandler
        @Dependency(\.serviceHandler) var handler
        @Dependency(\.standardOutput) var output
        let stopResult = processHandler.stop()
        output.write(stopResult)
        guard case .success = stopResult else { throw ExitCode.failure }
        let result = handler.install()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
    }
}

private struct ServiceUninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove login item"
    )

    func run() throws {
        @Dependency(\.processHandler) var processHandler
        @Dependency(\.serviceHandler) var handler
        @Dependency(\.standardOutput) var output
        let result = handler.uninstall()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
        let stopResult = processHandler.stop()
        output.write(stopResult)
        guard case .success = stopResult else { throw ExitCode.failure }
    }
}
