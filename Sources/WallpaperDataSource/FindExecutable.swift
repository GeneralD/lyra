import Foundation

func findExecutableInPath(_ name: String) -> String? {
    // Check well-known paths first (LaunchAgent may have minimal PATH)
    let knownPaths = [
        "/opt/homebrew/bin/\(name)",
        "/usr/local/bin/\(name)",
        "/usr/bin/\(name)",
        "/bin/\(name)",
    ]
    for path in knownPaths where FileManager.default.isExecutableFile(atPath: path) {
        return path
    }

    // Fall back to `which` for custom locations
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [name]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
