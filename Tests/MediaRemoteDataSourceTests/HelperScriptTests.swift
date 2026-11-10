import Foundation
import Testing

/// The helper is a resource interpreted by `/usr/bin/swift` at runtime (#261),
/// so the package build never compiles it: a syntax or type error would surface
/// only as a helper that dies at launch and a data source stuck on `.noInfo`.
/// Type-checking it here turns that silent runtime failure into a test failure.
@Suite("media-remote-helper script")
struct HelperScriptTests {
    private let scriptURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/MediaRemoteDataSource/Resources/media-remote-helper.swift")

    @Test("type-checks as a standalone script")
    func typeChecks() throws {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = ["-typecheck", scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        try process.run()
        // Drain before waiting: a full pipe would block the compiler forever.
        let diagnostics = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        #expect(process.terminationStatus == 0, "\(diagnostics)")
    }
}
