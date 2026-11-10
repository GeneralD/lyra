import Domain
import Foundation
import TestSupport

@testable import MediaRemoteDataSource

/// One helper output line in the multi-client frame format (#358).
func frameLine(systemPid: Int? = nil, clients: [[String: Any]]) -> String {
    let payload: [String: Any] = ["clients": clients]
        .merging(systemPid.map { ["system_pid": $0] } ?? [:]) { _, new in new }
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "" }
    return String(decoding: data, as: UTF8.self)
}

/// One `clients` entry of a frame line. Optional fields are omitted when `nil`,
/// mirroring how the helper drops values MediaRemote does not report.
func clientEntry(
    bundleID: String? = "com.example.player", pid: Int? = nil, title: String? = "Song",
    artist: String? = "Artist", duration: Double? = 123.0, elapsed: Double? = 4.5,
    rate: Double? = 1.0, timestamp: Double? = 10.0, artworkDigest: String? = nil,
    artworkBase64: String? = nil
) -> [String: Any] {
    let fields: [String: Any?] = [
        "bundle_id": bundleID, "pid": pid, "title": title, "artist": artist,
        "duration": duration, "elapsed": elapsed, "rate": rate, "timestamp": timestamp,
        "artwork_digest": artworkDigest, "artwork_base64": artworkBase64,
    ]
    return fields.compactMapValues { $0 }
}

/// A decoded `clients` entry, for tests that drive the pure types directly.
func helperClient(
    bundleID: String? = "com.example.player", pid: Int? = nil, title: String? = "Song",
    artist: String? = "Artist", rate: Double? = 1.0, timestamp: Double? = 10.0,
    artworkDigest: String? = nil, artworkBase64: String? = nil
) -> HelperClient {
    HelperClient(
        bundleID: bundleID, pid: pid, title: title, artist: artist, duration: 123.0,
        elapsed: 4.5, rate: rate, timestamp: timestamp, artworkDigest: artworkDigest,
        artworkBase64: artworkBase64)
}

final class CountingDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var decodeCallCount = 0

    var count: Int {
        lock.withLock { decodeCallCount }
    }

    @Sendable func decode(_ base64: String) -> Data? {
        lock.withLock {
            decodeCallCount += 1
            return Data(base64Encoded: base64)
        }
    }
}

struct CapturedCommand: Sendable {
    let executable: String
    let arguments: [String]
}

final class StreamingGateway: ProcessGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var streamPlans: [[String]]
    /// Opened by the test to let line 0 of each stream through; `nil` streams freely.
    private let firstLineGate: Collector<Void>?
    /// The index of every line a consumer asked for, recorded as its `next()` is entered.
    let nextRequests = Collector<Int>()
    private let gauge = InFlightGauge()
    /// The most `next()` calls that were ever in flight together, across every stream
    /// this gateway handed out; 1 means the subject serialised them.
    var peakConcurrentNextRequests: Int { gauge.peak }
    private(set) var runStreamingCallCount = 0
    private var capturedRunCommands: [CapturedCommand] = []
    private var capturedStreamingCommands: [CapturedCommand] = []

    init(
        streamPlans: [[String]],
        firstLineGate: Collector<Void>? = nil
    ) {
        self.streamPlans = streamPlans
        self.firstLineGate = firstLineGate
    }

    var runCommands: [CapturedCommand] {
        lock.withLock { capturedRunCommands }
    }

    var streamingCommands: [CapturedCommand] {
        lock.withLock { capturedStreamingCommands }
    }

    var resourceSnapshot: ResourceSnapshot { .init(cpuUser: 0, cpuSystem: 0, peakRSS: 0, currentRSS: 0) }
    var overlayPIDs: [Int32] { [] }
    func spawnDaemon(executablePath: String) -> Int32? { nil }
    func sendSignal(_ pid: Int32, signal: Int32) -> Bool { false }
    func isRunning(_ pid: Int32) -> Bool { false }
    func acquireLock() -> Bool { false }
    var isLocked: Bool { false }
    func releaseLock() {}
    func runLaunchctl(_ arguments: [String]) -> Int32 { 0 }
    func findExecutable(_ name: String) -> String? { nil }
    func run(executable: String, arguments: [String]) -> Int32 {
        lock.withLock {
            capturedRunCommands.append(CapturedCommand(executable: executable, arguments: arguments))
            return 0
        }
    }
    func runInteractiveShell(_ command: String) -> Int32 { 0 }
    func runCapturingOutput(executable: String, arguments: [String]) -> String? { nil }

    func runProcess(executable: String, arguments: [String], environment: [String: String]) async throws -> (
        status: Int32, stdout: String, stderr: String
    ) { fatalError("unused") }
    func runStreaming(executable: String, arguments: [String]) -> AsyncStream<String> {
        let lines: [String] = lock.withLock {
            runStreamingCallCount += 1
            capturedStreamingCommands.append(
                CapturedCommand(executable: executable, arguments: arguments))
            guard !streamPlans.isEmpty else { return [] }
            return streamPlans.removeFirst()
        }

        // `unfolding` runs the closure inside the consumer's `next()`, so the recording
        // and the gate sit exactly where the subject suspends: a test can observe that a
        // poll is *inside* `next()` instead of guessing it from a delay (#353).
        let cursor = LineCursor()
        return AsyncStream(unfolding: { [nextRequests, firstLineGate, gauge] in
            gauge.enter()
            defer { gauge.exit() }
            let index = cursor.advance()
            guard index < lines.count else { return nil }
            nextRequests.append(index)
            if index == 0, let firstLineGate { await firstLineGate.waitForCount(1) }
            return lines[index]
        })
    }
}

/// The next line index a stream hands out; a restarted stream begins at 0 again.
final class LineCursor: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0

    func advance() -> Int {
        lock.withLock {
            defer { index += 1 }
            return index
        }
    }
}

/// How many `next()` calls are in flight at once, and the most there ever were: the
/// subject is meant to serialise them, and the peak is what proves it did. The lock
/// keeps the count honest precisely when the subject fails to.
final class InFlightGauge: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private(set) var peak = 0

    func enter() {
        lock.withLock {
            inFlight += 1
            peak = max(peak, inFlight)
        }
    }

    func exit() {
        lock.withLock { inFlight -= 1 }
    }
}

/// Runs a task's jobs on its own queue and records each enqueue, so a test can observe
/// the task *suspending*: a `Task.yield()` re-enqueues the job, which is the only
/// externally visible trace of a spin-wait the subject keeps private.
@available(macOS 15, *)
final class ProbingExecutor: TaskExecutor {
    let enqueues = Collector<Void>()
    private let queue = DispatchQueue(label: "MediaRemoteDataSourceImplTests.ProbingExecutor")

    func enqueue(_ job: consuming ExecutorJob) {
        enqueues.append(())
        let unownedJob = UnownedJob(job)
        let executor = asUnownedTaskExecutor()
        queue.async { unownedJob.runSynchronously(on: executor) }
    }
}

extension Sequence {
    /// Sequential `map` over an async transform — each poll must see the
    /// previous one's effects, so the elements are never run concurrently.
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        for element in self { results.append(await transform(element)) }
        return results
    }
}

extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
