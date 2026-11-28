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
    func runInteractiveShell(_ command: String) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }
    func runProcess(executable: String, arguments: [String], environment: [String: String]) async throws -> (
        status: Int32, stdout: String, stderr: String
    ) { fatalError("unused") }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}

/// The plist names `brew services` writes: the current `sh.brew.*` and the legacy `homebrew.mxcl.*`.
private let homebrewPlistNames = ["sh.brew.lyra.plist", "homebrew.mxcl.lyra.plist"]

@Suite("ServiceHandlerImpl", .serialized)
struct ServiceHandlerImplTests {
    // MARK: - install

    @Suite("install", .serialized)
    struct Install {
        private let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-service-test-\(ProcessInfo.processInfo.processIdentifier)/install")

        @Test("returns managedByHomebrew when a brew services plist exists", arguments: homebrewPlistNames)
        func homebrewManaged(plistName: String) throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }
            try createFile(at: path, named: plistName)

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

        @Test("installReadiness refuses when a brew services plist exists", arguments: homebrewPlistNames)
        func readinessRefusesHomebrew(plistName: String) throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }
            try createFile(at: path, named: plistName)

            let readiness = ServiceHandlerImpl(launchAgentsPath: path).installReadiness
            #expect(readiness == .failure(.managedByHomebrew))
        }

        @Test("installReadiness is ready when no brew services plist exists")
        func readinessReady() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }

            let readiness = ServiceHandlerImpl(launchAgentsPath: path).installReadiness
            #expect(readiness == .success(.ready))
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

        @Test("writes ProcessType Interactive so launchd does not throttle the daemon")
        func writesInteractiveProcessType() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }

            withDependencies {
                $0.processGateway = StubGateway()
            } operation: {
                let handler = ServiceHandlerImpl(launchAgentsPath: path, executablePath: "/tmp/lyra")
                let result = handler.install()
                guard let plist = try? readPlist(from: path) else {
                    Issue.record("Failed to read generated plist")
                    return
                }
                #expect(result == .success(.installed(path: "\(path)/com.generald.lyra.plist")))
                #expect(plist["ProcessType"] as? String == "Interactive")
                #expect(plist["RunAtLoad"] as? Bool == true)
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

        @Test("returns managedByHomebrew when only a brew services plist exists", arguments: homebrewPlistNames)
        func homebrewManaged(plistName: String) throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }
            try createFile(at: path, named: plistName)

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

        @Test("returns failed when the plist cannot be deleted")
        func deleteFailure() throws {
            let path = tempDir.path
            try createDir(path)
            defer {
                // Restore writability first or cleanup cannot remove the plist.
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: path)
                cleanup(path)
            }
            try createFile(at: path, named: "com.generald.lyra.plist")
            // Removing a file needs write+execute on its directory — a 0555 dir
            // makes the real File.delete() throw through the production path.
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)

            withDependencies {
                $0.processGateway = StubGateway()
            } operation: {
                let handler = ServiceHandlerImpl(launchAgentsPath: path)
                let result = handler.uninstall()
                guard case .failure(.failed(let detail)) = result else {
                    Issue.record("Expected .failed, got \(result)")
                    return
                }
                #expect(detail == "Failed to delete plist file")
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

private func readPlist(from launchAgentsPath: String) throws -> [String: Any] {
    let plistPath = "\(launchAgentsPath)/com.generald.lyra.plist"
    let data = try Data(contentsOf: URL(fileURLWithPath: plistPath))
    return try #require(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
}

private func readProgramArguments(from launchAgentsPath: String) throws -> [String] {
    try #require(readPlist(from: launchAgentsPath)["ProgramArguments"] as? [String])
}
