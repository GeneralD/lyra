import AIService
import ArgumentParser
import Config
import Domain
import LRCLibService
import MusicBrainzService
import Foundation
import TOMLKit
import os

struct HealthcheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "healthcheck",
        abstract: "Check connectivity to external services"
    )

    func run() throws {
        let result = OSAllocatedUnfairLock(initialState: Int32(0))
        let done = OSAllocatedUnfairLock(initialState: false)

        Task {
            let code = await runChecks()
            result.withLock { $0 = code }
            done.withLock { $0 = true }
        }

        while !done.withLock({ $0 }) {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        let exitCode = result.withLock { $0 }
        guard exitCode == 0 else { throw ExitCode(rawValue: exitCode) }
    }
}

private extension HealthcheckCommand {
    func runChecks() async -> Int32 {
        let (config, configFailed) = validateConfig()

        let services: [any HealthCheckable] = [
            LRCLibAPI.search(query: "test"),
            MusicBrainzAPI.searchRecording(title: "test", artist: nil, duration: nil),
        ]

        var failed = configFailed ? 1 : 0

        for service in services {
            let result = await service.healthCheck()
            printResult(name: service.serviceName, result: result)
            if case .fail = result.status { failed += 1 }
        }

        if let aiConfig = config.ai {
            let aiService = OpenAICompatibleAPI(config: .init(
                endpoint: aiConfig.endpoint, model: aiConfig.model, apiKey: aiConfig.apiKey
            ))
            let result = await aiService.healthCheck()
            printResult(name: aiService.serviceName, result: result)
            if case .fail = result.status { failed += 1 }
        } else {
            printResult(name: "AI endpoint", result: HealthCheckResult(status: .skip, detail: "not configured"))
        }

        print("")
        switch failed {
        case 0:
            print("All checks passed.")
            return 0
        default:
            print("\(failed) check(s) failed.")
            return 1
        }
    }

    func validateConfig() -> (config: AppConfig, failed: Bool) {
        let home = NSHomeDirectory()
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] ?? "\(home)/.config"
        let candidates = [
            "\(xdgConfig)/lyra/config.toml",
            "\(home)/.lyra/config.toml",
            "\(xdgConfig)/lyra/config.json",
            "\(home)/.lyra/config.json",
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            printResult(name: "Config", result: HealthCheckResult(status: .pass, detail: "using defaults (no config file found)"))
            return (ConfigLoader.shared.load(), false)
        }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            printResult(name: "Config", result: HealthCheckResult(status: .fail, detail: "cannot read \(path)"))
            return (ConfigLoader.shared.load(), true)
        }
        do {
            if path.hasSuffix(".toml") {
                let table = try TOMLTable(string: content)
                _ = try TOMLDecoder().decode(AppConfig.self, from: table)
            } else {
                _ = try JSONDecoder().decode(AppConfig.self, from: content.data(using: .utf8) ?? Data())
            }
            printResult(name: "Config", result: HealthCheckResult(status: .pass, detail: "loaded (\(path))"))
            return (ConfigLoader.shared.load(), false)
        } catch {
            printResult(name: "Config", result: HealthCheckResult(status: .fail, detail: "decode error in \(path): \(error.localizedDescription)"))
            return (ConfigLoader.shared.load(), true)
        }
    }

    func printResult(name: String, result: HealthCheckResult) {
        let tag: String
        switch result.status {
        case .pass: tag = "[PASS]"
        case .fail: tag = "[FAIL]"
        case .skip: tag = "[SKIP]"
        }
        let padded = name.padding(toLength: 20, withPad: ".", startingAt: 0)
        print("\(tag) \(padded) \(result.detail)")
    }
}
