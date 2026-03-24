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
