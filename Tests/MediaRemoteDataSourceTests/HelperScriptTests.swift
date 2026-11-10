import Foundation
import TestSupport
import Testing

/// The helper is a resource interpreted by `/usr/bin/swift` at runtime (#261),
/// so the package build never compiles it: a syntax or type error would surface
/// only as a helper that dies at launch and a data source stuck on `.noInfo`.
/// Type-checking it here turns that silent runtime failure into a test failure.
@Suite("media-remote-helper script", .timeLimit(.minutes(1)))
struct HelperScriptTests {
    private let scriptURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/MediaRemoteDataSource/Resources/media-remote-helper.swift")

    /// `swiftc` takes seconds on a cold CI runner, so the exit is awaited, never
    /// joined: a blocked cooperative thread starved unrelated suites there.
    /// Diagnostics go to a file rather than a pipe, which nobody drains while
    /// the compiler runs.
    @Test("type-checks as a standalone script")
    func typeChecks() async throws {
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-remote-helper-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: diagnosticsURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: diagnosticsURL) }

        let exitStatus = Collector<Int32>()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = ["-typecheck", scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = try FileHandle(forWritingTo: diagnosticsURL)
        process.terminationHandler = { exitStatus.append($0.terminationStatus) }
        try process.run()

        await exitStatus.waitForCount(1)
        let status = exitStatus.values.first
        let diagnostics = (try? String(contentsOf: diagnosticsURL, encoding: .utf8)) ?? ""
        #expect(status == 0, "\(diagnostics)")
    }
}
