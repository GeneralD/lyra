import ArgumentParser
import AsyncRunnableCommand
import Dependencies
import Domain

struct ServiceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Manage login item service",
        subcommands: [ServiceInstallCommand.self, ServiceUninstallCommand.self]
    )
}

struct ServiceInstallCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Register as login item (LaunchAgent)"
    )

    func run() async throws {
        @Dependency(\.processHandler) var processHandler
        @Dependency(\.serviceHandler) var handler
        @Dependency(\.standardOutput) var output
        let readiness = handler.installReadiness
        output.write(readiness)
        guard case .success = readiness else { throw ExitCode.failure }
        let stopResult = await processHandler.stop()
        output.write(stopResult)
        guard case .success = stopResult else { throw ExitCode.failure }
        let result = handler.install()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
    }
}

struct ServiceUninstallCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove login item"
    )

    func run() async throws {
        @Dependency(\.processHandler) var processHandler
        @Dependency(\.serviceHandler) var handler
        @Dependency(\.standardOutput) var output
        let result = handler.uninstall()
        output.write(result)
        guard case .success = result else { throw ExitCode.failure }
        let stopResult = await processHandler.stop()
        output.write(stopResult)
        guard case .success = stopResult else { throw ExitCode.failure }
    }
}
