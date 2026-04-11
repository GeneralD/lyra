import Dependencies
import Domain
import Foundation
import Testing

@testable import ServiceHandler

private struct StubGateway: ProcessGateway {
    var executables: [String: String] = [:]
    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { [] }
    func spawnDaemon(executablePath: String) -> Int32? { nil }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { false }
    func isRunning(_ pid: Int32) -> Bool { false }
    func acquireLock() -> Bool { false }
    var isLocked: Bool { false }
    func releaseLock() {}
    func runLaunchctl(_ arguments: [String]) -> Int32 { 0 }
    func findExecutable(_ name: String) -> String? { executables[name] }
    func run(executable: String, arguments: [String]) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}

@Suite("ServiceHandlerImpl", .serialized)
struct ServiceHandlerImplTests {
    // MARK: - install

    @Suite("install", .serialized)
    struct Install {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-service-test-\(ProcessInfo.processInfo.processIdentifier)/install")

        @Test("returns managedByHomebrew when homebrew plist exists")
        func homebrewManaged() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }
            try createFile(at: path, named: "homebrew.mxcl.lyra.plist")

            withDependencies {
                $0.processGateway = StubGateway()
            } operation: {
                let handler = ServiceHandlerImpl(launchAgentsPath: path)
                let result = handler.install()
                guard case .failure(.managedByHomebrew) = result else {
                    Issue.record("Expected .managedByHomebrew, got \(result)")
                    return
                }
            }
        }

        @Test("creates plist file when no homebrew conflict")
        func createsPlist() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }

            withDependencies {
                $0.processGateway = StubGateway()
            } operation: {
                let handler = ServiceHandlerImpl(launchAgentsPath: path)
                let result = handler.install()
                let plistExists = FileManager.default.fileExists(
                    atPath: "\(path)/com.generald.lyra.plist"
                )
                #expect(plistExists)
                switch result {
                case .success(.installed): break
                case .failure(.bootstrapFailed): break
                default: Issue.record("Unexpected result: \(result)")
                }
            }
        }

        @Test("writes current executable when not installed via mint or PATH")
        func usesCurrentExecutablePath() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }

            let executablePath = "/tmp/lyra"
            withDependencies {
                $0.processGateway = StubGateway()
            } operation: {
                let handler = ServiceHandlerImpl(
                    launchAgentsPath: path,
                    executablePath: executablePath
                )
                let result = handler.install()
                guard let programArguments = try? readProgramArguments(from: path) else {
                    Issue.record("Failed to read ProgramArguments from generated plist")
                    return
                }
                #expect(result == .success(.installed(path: "\(path)/com.generald.lyra.plist")))
                #expect(programArguments == [executablePath, "daemon"])
            }
        }

        @Test("writes mint invocation when current executable is under .mint")
        func usesMintProgramArguments() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }

            withDependencies {
                $0.processGateway = StubGateway(executables: ["mint": "/opt/homebrew/bin/mint"])
            } operation: {
                let handler = ServiceHandlerImpl(
                    launchAgentsPath: path,
                    executablePath: "/Users/test/.mint/bin/lyra"
                )
                let result = handler.install()
                guard let programArguments = try? readProgramArguments(from: path) else {
                    Issue.record("Failed to read ProgramArguments from generated plist")
                    return
                }
                #expect(result == .success(.installed(path: "\(path)/com.generald.lyra.plist")))
                #expect(programArguments == ["/opt/homebrew/bin/mint", "run", "GeneralD/lyra", "daemon"])
            }
        }

        @Test("prefers installed executable found on PATH")
        func usesInstalledExecutableFromPath() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }

            let executablePath = "/Applications/Lyra.app/Contents/MacOS/lyra"
            withDependencies {
                $0.processGateway = StubGateway(executables: ["lyra": "/usr/local/bin/lyra"])
            } operation: {
                let handler = ServiceHandlerImpl(
                    launchAgentsPath: path,
                    executablePath: executablePath
                )
                let result = handler.install()
                guard let programArguments = try? readProgramArguments(from: path) else {
                    Issue.record("Failed to read ProgramArguments from generated plist")
                    return
                }
                #expect(result == .success(.installed(path: "\(path)/com.generald.lyra.plist")))
                #expect(programArguments == ["/usr/local/bin/lyra", "daemon"])
            }
        }
    }

    // MARK: - uninstall

    @Suite("uninstall", .serialized)
    struct Uninstall {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-service-test-\(ProcessInfo.processInfo.processIdentifier)/uninstall")

        @Test("returns notInstalled when no plist files exist")
        func notInstalled() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }

            withDependencies {
                $0.processGateway = StubGateway()
            } operation: {
                let handler = ServiceHandlerImpl(launchAgentsPath: path)
                let result = handler.uninstall()
                guard case .failure(.notInstalled) = result else {
                    Issue.record("Expected .notInstalled, got \(result)")
                    return
                }
            }
        }

        @Test("returns managedByHomebrew when only homebrew plist exists")
        func homebrewManaged() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }
            try createFile(at: path, named: "homebrew.mxcl.lyra.plist")

            withDependencies {
                $0.processGateway = StubGateway()
            } operation: {
                let handler = ServiceHandlerImpl(launchAgentsPath: path)
                let result = handler.uninstall()
                guard case .failure(.managedByHomebrew) = result else {
                    Issue.record("Expected .managedByHomebrew, got \(result)")
                    return
                }
            }
        }

        @Test("deletes plist and returns uninstalled")
        func deletePlist() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }
            try createFile(at: path, named: "com.generald.lyra.plist")

            withDependencies {
                $0.processGateway = StubGateway()
            } operation: {
                let handler = ServiceHandlerImpl(launchAgentsPath: path)
                let result = handler.uninstall()
                guard case .success(.uninstalled) = result else {
                    Issue.record("Expected .uninstalled, got \(result)")
                    return
                }
                let plistExists = FileManager.default.fileExists(
                    atPath: "\(path)/com.generald.lyra.plist"
                )
                #expect(!plistExists)
            }
        }
    }
}

// MARK: - Helpers

private func createDir(_ path: String) throws {
    try FileManager.default.createDirectory(
        atPath: path, withIntermediateDirectories: true
    )
}

private func createFile(at dir: String, named name: String) throws {
    let filePath = "\(dir)/\(name)"
    guard FileManager.default.createFile(atPath: filePath, contents: Data()) else {
        struct FileCreationError: Error {}
        throw FileCreationError()
    }
}

private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

private func readProgramArguments(from launchAgentsPath: String) throws -> [String] {
    let plistPath = "\(launchAgentsPath)/com.generald.lyra.plist"
    let data = try Data(contentsOf: URL(fileURLWithPath: plistPath))
    let plist = try #require(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
    return try #require(plist["ProgramArguments"] as? [String])
}
