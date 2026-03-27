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
import Foundation

private let appVersion: String = {
    guard let url = Bundle.module.url(forResource: "version", withExtension: "txt"),
        let content = try? String(contentsOf: url, encoding: .utf8)
    else { return "unknown" }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}()

public struct RootCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "lyra",
        abstract: "Desktop lyrics overlay, video wallpaper, and more",
        version: appVersion,
        subcommands: [
            StartCommand.self,
            StopCommand.self,
            RestartCommand.self,
            ServiceCommand.self,
            CompletionCommand.self,
            VersionCommand.self,
            DaemonCommand.self,
            HealthcheckCommand.self,
            ConfigCommand.self,
        ],
        defaultSubcommand: StartCommand.self
    )

    public init() {}
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show version"
    )

    func run() {
        print(RootCommand.configuration.version)
    }
}