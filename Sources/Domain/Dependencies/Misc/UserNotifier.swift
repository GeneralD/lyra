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

import Dependencies
import Foundation

public protocol UserNotifier: Sendable {
    func notify(title: String, subtitle: String?, message: String, fileToOpen: String?)
}

extension UserNotifier {
    public func notify(title: String, subtitle: String?, message: String) {
        notify(title: title, subtitle: subtitle, message: message, fileToOpen: nil)
    }
}

public enum UserNotifierKey: DependencyKey {
    public static let liveValue: any UserNotifier = OSAScriptNotifier()
    public static let testValue: any UserNotifier = NoopUserNotifier()
}

extension DependencyValues {
    public var userNotifier: any UserNotifier {
        get { self[UserNotifierKey.self] }
        set { self[UserNotifierKey.self] = newValue }
    }
}

private struct NoopUserNotifier: UserNotifier {
    func notify(title: String, subtitle: String?, message: String, fileToOpen: String?) {}
}

private struct OSAScriptNotifier: UserNotifier {
    func notify(title: String, subtitle: String?, message: String, fileToOpen: String?) {
        let escaped = String(message.prefix(300))
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        let subtitleLine = subtitle.map { "\"\($0)\n\n\" & " } ?? ""
        let buttons =
            fileToOpen != nil
            ? "buttons {\"Open Config\", \"Dismiss\"} default button \"Dismiss\""
            : "buttons {\"OK\"} default button \"OK\""
        let script = """
            set result to display alert "\(title)" \
            message (\(subtitleLine)"\(escaped)") \
            \(buttons)
            """
        let openScript =
            fileToOpen.map { path in
                """

                if button returned of result is "Open Config" then
                    do shell script "open '\(path)'"
                end if
                """
            } ?? ""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script + openScript]
        try? process.run()
        process.waitUntilExit()
    }
}