// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import ArgumentParser
import Dependencies
import Domain
import Foundation
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

extension HealthcheckCommand {
    fileprivate func runChecks() async -> Int32 {
        @Dependency(\.healthCheckers) var checkers

        var failed = 0
        for checker in checkers {
            let result = await checker.healthCheck()
            printResult(name: checker.serviceName, result: result)
            if case .fail = result.status { failed += 1 }
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

    fileprivate func printResult(name: String, result: HealthCheckResult) {
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