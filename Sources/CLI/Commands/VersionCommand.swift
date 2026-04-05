import ArgumentParser
import Dependencies
import Domain

var appVersion: String {
    @Dependency(\.versionHandler) var handler
    return handler.version
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show version"
    )

    func run() {
        print(appVersion)
    }
}
