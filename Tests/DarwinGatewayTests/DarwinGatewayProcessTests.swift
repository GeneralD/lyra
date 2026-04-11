import Foundation
import Testing

@testable import DarwinGateway

@Suite("DarwinGateway process operations", .serialized)
struct DarwinGatewayProcessTests {
    private let gateway = DarwinGateway()

    @Test("resourceSnapshot returns non-negative counters")
    func resourceSnapshotNonNegative() {
        let snapshot = gateway.resourceSnapshot

        #expect(snapshot.cpuUser >= 0)
        #expect(snapshot.cpuSystem >= 0)
        #expect(snapshot.peakRSS >= 0)
        #expect(snapshot.currentRSS >= 0)
    }

    @Test("overlayPIDs includes lyra-named helper process")
    func overlayPIDsIncludesMatchingProcess() throws {
        let helper = try ProcessHelper.launchLyraNamedSleepProcess()
        defer { ProcessHelper.terminate(helper) }

        try ProcessHelper.waitUntilRunning(helper.processIdentifier)

        let pids = gateway.overlayPIDs
        #expect(pids.contains(helper.processIdentifier))
    }

    @Test("spawnDaemon returns running pid for long-lived executable")
    func spawnDaemonReturnsRunningPID() throws {
        let executable = try ProcessHelper.makeDaemonScript()
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }

        guard let pid = gateway.spawnDaemon(executablePath: executable.path) else {
            Issue.record("spawnDaemon should return a pid for a long-lived executable")
            return
        }
        defer { _ = gateway.sendSignal(pid, signal: SIGKILL) }

        #expect(gateway.isRunning(pid))
    }

    @Test("sendSignal terminates running process")
    func sendSignalTerminatesProcess() throws {
        let process = try ProcessHelper.launchSleepProcess()
        defer { ProcessHelper.terminate(process) }

        try ProcessHelper.waitUntilRunning(process.processIdentifier)

        #expect(gateway.isRunning(process.processIdentifier))
        #expect(gateway.sendSignal(process.processIdentifier, signal: SIGTERM))
        process.waitUntilExit()
        #expect(!gateway.isRunning(process.processIdentifier))
    }

    @Test("run returns child termination status")
    func runReturnsTerminationStatus() {
        let status = gateway.run(executable: "/usr/bin/true", arguments: [])
        #expect(status == 0)
    }

    @Test("runLaunchctl returns launchctl exit status")
    func runLaunchctlReturnsStatus() {
        let status = gateway.runLaunchctl(["help"])
        #expect(status == 0)
    }

    @Test("findExecutable resolves known executable")
    func findExecutableResolvesPath() {
        let path = gateway.findExecutable("sh")

        #expect(path != nil)
        if let path {
            #expect(URL(fileURLWithPath: path).lastPathComponent == "sh")
            #expect(FileManager.default.isExecutableFile(atPath: path))
        }
    }

    @Test("findExecutable returns nil for missing command")
    func findExecutableReturnsNilForMissingCommand() {
        #expect(gateway.findExecutable("lyra-command-that-does-not-exist") == nil)
    }

    @Test("runCapturingOutput returns trimmed stdout")
    func runCapturingOutputReturnsTrimmedStdout() {
        let output = gateway.runCapturingOutput(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'hello\\n'"]
        )

        #expect(output == "hello")
    }

    @Test("runCapturingOutput returns nil on non-zero exit")
    func runCapturingOutputReturnsNilOnFailure() {
        let output = gateway.runCapturingOutput(
            executable: "/bin/sh",
            arguments: ["-c", "exit 7"]
        )

        #expect(output == nil)
    }

    @Test("runStreaming yields lines and flushes final unterminated line")
    func runStreamingYieldsLinesAndFinalBuffer() async {
        let stream = gateway.runStreaming(
            executable: "/bin/sh",
            arguments: ["-c", "printf 'first\\nsecond'"]
        )

        var collected: [String] = []
        for await line in stream {
            collected.append(line)
        }

        #expect(collected == ["first", "second"])
    }
}

private enum ProcessHelper {
    static func makeDaemonScript() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-darwin-gateway-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let script = dir.appendingPathComponent("daemon-script.sh")
        let body = """
            #!/bin/sh
            sleep 600
            """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    static func launchSleepProcess() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 600"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    static func launchLyraNamedSleepProcess() throws -> Process {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyra-overlay-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let symlink = dir.appendingPathComponent("lyra-helper")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))

        let process = Process()
        process.executableURL = symlink
        process.arguments = ["600"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    static func waitUntilRunning(_ pid: Int32, timeout: TimeInterval = 5) throws {
        let gateway = DarwinGateway()
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if gateway.isRunning(pid) {
                return
            }
            usleep(50_000)
        }

        struct Timeout: Error {}
        throw Timeout()
    }

    static func terminate(_ process: Process) {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        if let url = process.executableURL?.deletingLastPathComponent(),
            url.path.contains("/var/") || url.path.contains("/tmp/") || url.path.contains("/private/tmp/")
        {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
