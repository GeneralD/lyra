import Foundation
import Testing

@testable import ServiceHandler

@Suite("ServiceHandlerImpl", .serialized)
struct ServiceHandlerImplSpec {
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

            let handler = ServiceHandlerImpl(launchAgentsPath: path)
            let result = handler.install()
            guard case .failure(.managedByHomebrew) = result else {
                Issue.record("Expected .managedByHomebrew, got \(result)")
                return
            }
        }

        @Test("creates plist file when no homebrew conflict")
        func createsPlist() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }

            let handler = ServiceHandlerImpl(launchAgentsPath: path)
            let result = handler.install()
            // bootstrap will fail in test environment (no launchd), but plist should be created
            let plistExists = FileManager.default.fileExists(
                atPath: "\(path)/com.generald.lyra.plist"
            )
            #expect(plistExists)
            // Result is either .installed or .bootstrapFailed depending on launchctl
            switch result {
            case .success(.installed): break  // OK
            case .failure(.bootstrapFailed): break  // expected in test env
            default: Issue.record("Unexpected result: \(result)")
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

            let handler = ServiceHandlerImpl(launchAgentsPath: path)
            let result = handler.uninstall()
            guard case .failure(.notInstalled) = result else {
                Issue.record("Expected .notInstalled, got \(result)")
                return
            }
        }

        @Test("returns managedByHomebrew when only homebrew plist exists")
        func homebrewManaged() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }
            try createFile(at: path, named: "homebrew.mxcl.lyra.plist")

            let handler = ServiceHandlerImpl(launchAgentsPath: path)
            let result = handler.uninstall()
            guard case .failure(.managedByHomebrew) = result else {
                Issue.record("Expected .managedByHomebrew, got \(result)")
                return
            }
        }

        @Test("deletes plist and returns uninstalled")
        func deletePlist() throws {
            let path = tempDir.path
            try createDir(path)
            defer { cleanup(path) }
            try createFile(at: path, named: "com.generald.lyra.plist")

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
