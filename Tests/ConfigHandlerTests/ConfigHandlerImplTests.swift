import Dependencies
import Domain
import Testing
import os

@testable import ConfigHandler

@Suite("ConfigHandlerImpl")
struct ConfigHandlerImplTests {
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

    // MARK: - editConfig

    @Suite("editConfig")
    struct EditConfig {
        @Test("returns failure when editor is unset")
        func editorUnset() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { nil },
                operation: { $0.editConfig() }
            )

            #expect(result == .failure(.failed(detail: "$EDITOR is not set. Set it with: export EDITOR=vim")))
            #expect(gateway.interactiveRunCalls.isEmpty)
        }

        @Test("returns failure when editor is whitespace only")
        func editorWhitespace() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "   \n\t" },
                operation: { $0.editConfig() }
            )

            #expect(result == .failure(.failed(detail: "$EDITOR is not set. Set it with: export EDITOR=vim")))
            #expect(gateway.interactiveRunCalls.isEmpty)
        }

        @Test("invokes editor via /bin/sh with single-quoted path")
        func invokesViaShell() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "vim" },
                operation: { $0.editConfig() }
            )

            #expect(result == .success(.launched(path: "/tmp/config.toml")))
            #expect(
                gateway.interactiveRunCalls == [
                    ProcessRunCall(executable: "/bin/sh", arguments: ["-c", "vim '/tmp/config.toml'"])
                ]
            )
        }

        @Test("passes editor flags through to shell unchanged")
        func passesEditorFlags() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "code --wait" },
                operation: { $0.editConfig() }
            )

            #expect(result == .success(.launched(path: "/tmp/config.toml")))
            #expect(
                gateway.interactiveRunCalls == [
                    ProcessRunCall(executable: "/bin/sh", arguments: ["-c", "code --wait '/tmp/config.toml'"])
                ]
            )
        }

        @Test("escapes single quote in config path")
        func escapesSingleQuote() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/it's/config.toml",
                processGateway: gateway,
                editorProvider: { "vim" },
                operation: { $0.editConfig() }
            )

            #expect(result == .success(.launched(path: "/tmp/it's/config.toml")))
            #expect(
                gateway.interactiveRunCalls == [
                    ProcessRunCall(executable: "/bin/sh", arguments: ["-c", "vim '/tmp/it'\\''s/config.toml'"])
                ]
            )
        }

        @Test("trims surrounding whitespace from editor value")
        func trimsWhitespace() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "  vim  " },
                operation: { $0.editConfig() }
            )

            #expect(result == .success(.launched(path: "/tmp/config.toml")))
            #expect(
                gateway.interactiveRunCalls == [
                    ProcessRunCall(executable: "/bin/sh", arguments: ["-c", "vim '/tmp/config.toml'"])
                ]
            )
        }

        @Test("returns failure when editor exits non-zero")
        func editorFailure() {
            let gateway = ProcessGatewaySpy(runStatus: 7)
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "false" },
                operation: { $0.editConfig() }
            )

            #expect(result == .failure(.failed(detail: "Editor command failed with exit status 7")))
        }

        @Test("returns launch failure when shell cannot start")
        func editorLaunchFailure() {
            let gateway = ProcessGatewaySpy(runStatus: -1)
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "vim" },
                operation: { $0.editConfig() }
            )

            #expect(result == .failure(.failed(detail: "Editor process failed to launch")))
        }
    }

    // MARK: - openConfig

    @Suite("openConfig")
    struct OpenConfig {
        @Test("launches open through process gateway")
        func launchesOpen() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway
            ) {
                $0.openConfig()
            }

            #expect(result == .success(.launched(path: "/tmp/config.toml")))
            #expect(
                gateway.interactiveRunCalls == [
                    ProcessRunCall(executable: "/usr/bin/open", arguments: ["/tmp/config.toml"])
                ]
            )
        }

        @Test("returns failure when open exits non-zero")
        func openFailure() {
            let gateway = ProcessGatewaySpy(runStatus: 1)
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway
            ) {
                $0.openConfig()
            }

            #expect(result == .failure(.failed(detail: "Open command failed with exit status 1")))
        }

        @Test("returns launch failure when open process cannot start")
        func openLaunchFailure() {
            let gateway = ProcessGatewaySpy(runStatus: -1)
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway
            ) {
                $0.openConfig()
            }

            #expect(result == .failure(.failed(detail: "Open process failed to launch")))
        }

        @Test("returns config path failure without launching")
        func configPathFailure() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: nil,
                writeError: true,
                processGateway: gateway
            ) {
                $0.openConfig()
            }

            guard case .failure = result else {
                Issue.record("Expected failure")
                return
            }
            #expect(gateway.runCalls.isEmpty)
            #expect(gateway.interactiveRunCalls.isEmpty)
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
    processGateway: (any ProcessGateway)? = nil,
    editorProvider: @escaping @Sendable () -> String? = { "vi" },
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
        if let processGateway {
            $0.processGateway = processGateway
        }
    } operation: {
        operation(ConfigHandlerImpl(editorProvider: editorProvider))
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

private struct ProcessRunCall: Equatable {
    var executable: String
    var arguments: [String]
}

private final class ProcessGatewaySpy: ProcessGateway, @unchecked Sendable {
    private(set) var runCalls: [ProcessRunCall] = []
    private(set) var interactiveRunCalls: [ProcessRunCall] = []
    private let runStatus: Int32

    init(runStatus: Int32 = 0) {
        self.runStatus = runStatus
    }

    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { [] }
    func spawnDaemon(executablePath: String) -> Int32? { nil }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { false }
    func isRunning(_ pid: Int32) -> Bool { false }
    func acquireLock() -> Bool { false }
    var isLocked: Bool { false }
    func releaseLock() {}
    func runLaunchctl(_ arguments: [String]) -> Int32 { runStatus }
    func findExecutable(_ name: String) -> String? { nil }
    func run(executable: String, arguments: [String]) -> Int32 {
        runCalls.append(ProcessRunCall(executable: executable, arguments: arguments))
        return runStatus
    }
    func runInteractive(executable: String, arguments: [String]) -> Int32 {
        interactiveRunCalls.append(ProcessRunCall(executable: executable, arguments: arguments))
        return runStatus
    }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }
}
