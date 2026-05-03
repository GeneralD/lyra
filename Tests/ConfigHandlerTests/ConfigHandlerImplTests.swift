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
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .failure(.failed(detail: "$EDITOR is not set. Set it with: export EDITOR=vim")))
            #expect(gateway.runCalls.isEmpty)
            #expect(gateway.interactiveRunCalls.isEmpty)
        }

        @Test("returns failure when editor is whitespace")
        func editorWhitespace() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "   " },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .failure(.failed(detail: "$EDITOR is not set. Set it with: export EDITOR=vim")))
            #expect(gateway.runCalls.isEmpty)
            #expect(gateway.interactiveRunCalls.isEmpty)
        }

        @Test("launches editor through process gateway")
        func launchesEditor() {
            let gateway = ProcessGatewaySpy(executablePaths: ["code": "/usr/local/bin/code"])
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "code --wait" },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .success(.launched(path: "/tmp/config.toml")))
            #expect(
                gateway.interactiveRunCalls == [
                    ProcessRunCall(
                        executable: "/usr/local/bin/code",
                        arguments: ["--wait", "/tmp/config.toml"]
                    )
                ]
            )
        }

        @Test("preserves quoted editor arguments")
        func quotedEditorArguments() {
            let gateway = ProcessGatewaySpy(executablePaths: ["code": "/usr/local/bin/code"])
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { #"code --profile "Lyra Dev" --wait"# },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .success(.launched(path: "/tmp/config.toml")))
            #expect(
                gateway.interactiveRunCalls == [
                    ProcessRunCall(
                        executable: "/usr/local/bin/code",
                        arguments: ["--profile", "Lyra Dev", "--wait", "/tmp/config.toml"]
                    )
                ]
            )
        }

        @Test("launches editor from quoted executable path")
        func quotedExecutablePath() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { #""/Applications/Code App/code" --wait"# },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .success(.launched(path: "/tmp/config.toml")))
            #expect(
                gateway.interactiveRunCalls == [
                    ProcessRunCall(
                        executable: "/Applications/Code App/code",
                        arguments: ["--wait", "/tmp/config.toml"]
                    )
                ]
            )
        }

        @Test("preserves escaped editor arguments")
        func escapedEditorArguments() {
            let gateway = ProcessGatewaySpy(executablePaths: ["code": "/usr/local/bin/code"])
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { #"code foo\ bar "baz\"qux""# },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .success(.launched(path: "/tmp/config.toml")))
            #expect(
                gateway.interactiveRunCalls == [
                    ProcessRunCall(
                        executable: "/usr/local/bin/code",
                        arguments: ["foo bar", "baz\"qux", "/tmp/config.toml"]
                    )
                ]
            )
        }

        @Test("returns failure when editor contains newline")
        func editorNewline() {
            let gateway = ProcessGatewaySpy(executablePaths: ["code": "/usr/local/bin/code"])
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "code\n--wait" },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .failure(.failed(detail: "$EDITOR must not contain newline characters")))
            #expect(gateway.interactiveRunCalls.isEmpty)
        }

        @Test("returns failure when editor command is empty after parsing")
        func editorEmptyCommand() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "\"\"" },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .failure(.failed(detail: "$EDITOR does not contain an executable command")))
            #expect(gateway.interactiveRunCalls.isEmpty)
        }

        @Test("returns failure when editor has unfinished escape")
        func editorUnfinishedEscape() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "code\\" },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .failure(.failed(detail: "$EDITOR ends with an unfinished escape")))
            #expect(gateway.interactiveRunCalls.isEmpty)
        }

        @Test("returns failure when editor has unclosed quote")
        func editorUnclosedQuote() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { #"code "unterminated"# },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .failure(.failed(detail: "$EDITOR contains an unclosed quote")))
            #expect(gateway.interactiveRunCalls.isEmpty)
        }

        @Test("returns failure when editor executable is missing")
        func editorExecutableMissing() {
            let gateway = ProcessGatewaySpy()
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "code --wait" },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .failure(.failed(detail: "Editor executable not found: code")))
            #expect(gateway.interactiveRunCalls.isEmpty)
        }

        @Test("returns failure when editor exits non-zero")
        func editorFailure() {
            let gateway = ProcessGatewaySpy(runStatus: 7, executablePaths: ["false": "/usr/bin/false"])
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "false" },
                operation: {
                    $0.editConfig()
                }
            )

            #expect(result == .failure(.failed(detail: "Editor command failed with exit status 7")))
        }

        @Test("returns launch failure when editor process cannot start")
        func editorLaunchFailure() {
            let gateway = ProcessGatewaySpy(runStatus: -1, executablePaths: ["missing-editor": "/missing/editor"])
            let result = withConfig(
                existingPath: "/tmp/config.toml",
                processGateway: gateway,
                editorProvider: { "missing-editor" },
                operation: {
                    $0.editConfig()
                }
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
    private let executablePaths: [String: String]

    init(runStatus: Int32 = 0, executablePaths: [String: String] = [:]) {
        self.runStatus = runStatus
        self.executablePaths = executablePaths
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
    func findExecutable(_ name: String) -> String? { executablePaths[name] }
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
