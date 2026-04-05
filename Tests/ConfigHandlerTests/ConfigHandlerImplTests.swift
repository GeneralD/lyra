import Dependencies
import Domain
import Testing
import os

@testable import ConfigHandler

@Suite("ConfigHandlerImpl")
struct ConfigHandlerImplSpec {
    // MARK: - template

    @Suite("template")
    struct Template {
        @Test("returns template string from UseCase")
        func returnsTemplate() {
            let result = withConfig(template: "# config") { $0.template(format: .toml) }
            #expect(result == "# config")
        }

        @Test("returns nil when UseCase returns nil")
        func returnsNil() {
            let result = withConfig(template: nil) { $0.template(format: .toml) }
            #expect(result == nil)
        }
    }

    // MARK: - writeTemplate

    @Suite("writeTemplate")
    struct WriteTemplate {
        @Test("returns success with path on UseCase success")
        func success() {
            let result = withConfig(writePath: "/tmp/config.toml") {
                $0.writeTemplate(format: .toml, force: false)
            }
            guard case .success(.created(let path)) = result else {
                Issue.record("Expected success")
                return
            }
            #expect(path == "/tmp/config.toml")
        }

        @Test("returns failure when UseCase throws")
        func failure() {
            let result = withConfig(writeError: true) {
                $0.writeTemplate(format: .toml, force: false)
            }
            guard case .failure = result else {
                Issue.record("Expected failure")
                return
            }
        }

        @Test("passes force parameter through")
        func forceParam() {
            let tracker = ForceTracker()
            _ = withConfig(forceTracker: tracker) {
                $0.writeTemplate(format: .toml, force: true)
            }
            #expect(tracker.lastForce == true)
        }
    }

    // MARK: - configPath

    @Suite("configPath")
    struct ConfigPath {
        @Test("returns existing path when config file exists")
        func existingPath() {
            let result = withConfig(existingPath: "/home/.config/lyra/config.toml") {
                $0.configPath()
            }
            guard case .success(.found(let path)) = result else {
                Issue.record("Expected success")
                return
            }
            #expect(path == "/home/.config/lyra/config.toml")
        }

        @Test("creates config and returns path when no existing file")
        func createsNew() {
            let result = withConfig(existingPath: nil, writePath: "/tmp/new.toml") {
                $0.configPath()
            }
            guard case .success(.found(let path)) = result else {
                Issue.record("Expected success")
                return
            }
            #expect(path == "/tmp/new.toml")
        }

        @Test("returns failure when no existing file and write fails")
        func createFails() {
            let result = withConfig(existingPath: nil, writeError: true) {
                $0.configPath()
            }
            guard case .failure = result else {
                Issue.record("Expected failure")
                return
            }
        }
    }
}

// MARK: - Helpers

private final class ForceTracker: Sendable {
    private let _force = OSAllocatedUnfairLock(initialState: false)
    var lastForce: Bool { _force.withLock { $0 } }
    func set(_ value: Bool) { _force.withLock { $0 = value } }
}

private func withConfig<T>(
    template: String? = nil,
    existingPath: String? = nil,
    writePath: String? = "/tmp/config.toml",
    writeError: Bool = false,
    forceTracker: ForceTracker? = nil,
    operation: (ConfigHandlerImpl) -> T
) -> T {
    withDependencies {
        $0.configUseCase = StubConfigUseCase(
            templateResult: template,
            existingPath: existingPath,
            writePath: writePath,
            writeError: writeError,
            forceTracker: forceTracker
        )
    } operation: {
        operation(ConfigHandlerImpl())
    }
}

private struct StubConfigUseCase: ConfigUseCase {
    var templateResult: String?
    var existingPath: String?
    var writePath: String?
    var writeError: Bool = false
    var forceTracker: ForceTracker?

    var appStyle: AppStyle { .init() }
    var existingConfigPath: String? { existingPath }

    func template(format: ConfigFormat) -> String? { templateResult }

    func writeTemplate(format: ConfigFormat, force: Bool) throws -> String {
        forceTracker?.set(force)
        if writeError { throw ConfigWriteError.fileExists }
        return writePath ?? ""
    }
}

private enum ConfigWriteError: Error {
    case fileExists
}
