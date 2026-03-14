import Foundation
import Testing

@Suite("CompletionCommand E2E")
struct CompletionCommandTests {
    @Test("zsh completion output matches resource file")
    func zshCompletion() throws {
        let output = try runBackdrop(arguments: ["completion", "zsh"])
        let expected = try String(contentsOfFile: resourcePath("backdrop.zsh"), encoding: .utf8)
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines)
            == expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("bash completion output matches resource file")
    func bashCompletion() throws {
        let output = try runBackdrop(arguments: ["completion", "bash"])
        let expected = try String(contentsOfFile: resourcePath("backdrop.bash"), encoding: .utf8)
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines)
            == expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("unsupported shell returns error")
    func unsupportedShell() throws {
        let process = Process()
        process.executableURL = binaryURL()
        process.arguments = ["completion", "fish"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus != 0)
    }
}

private func runBackdrop(arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = binaryURL()
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

private func binaryURL() -> URL {
    packageRoot().appendingPathComponent(".build/debug/backdrop")
}

private func resourcePath(_ filename: String) -> String {
    packageRoot().appendingPathComponent("Sources/BackdropCLI/Resources/\(filename)").path
}

private func packageRoot() -> URL {
    var dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CompletionCommandTests.swift
        .deletingLastPathComponent() // BackdropCLITests
        .deletingLastPathComponent() // Tests
    return dir
}
