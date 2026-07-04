import Foundation
import Testing

@testable import DarwinGateway

@Suite("DarwinGateway runStreaming", .serialized)
struct DarwinGatewayRunStreamingTests {
    private let gateway = DarwinGateway()

    @Test("delivers the first line before the child process exits (#295)", .timeLimit(.minutes(1)))
    func deliversFirstLineBeforeProcessExit() async {
        // The child emits one line, then blocks. The stream must deliver that
        // first line promptly — not wait for the process to finish. This is the
        // regression path for #295: the first line never reached a consumer
        // whose calling thread was blocked on a semaphore, because it was
        // yielded from a raw GCD thread instead of the cooperative pool.
        let stream = gateway.runStreaming(
            executable: "/bin/sh", arguments: ["-c", "printf 'ready\\n'; sleep 30"])
        var iterator = stream.makeAsyncIterator()

        let first = await iterator.next()

        #expect(first == "ready")
        // Dropping the iterator terminates the still-sleeping child via onTermination.
    }

    @Test("delivers many lines in order", .timeLimit(.minutes(1)))
    func deliversManyLinesInOrder() async {
        let stream = gateway.runStreaming(
            executable: "/bin/sh", arguments: ["-c", "for i in 1 2 3 4 5; do echo $i; done"])

        let collected = await stream.reduce(into: [String]()) { $0.append($1) }

        #expect(collected == ["1", "2", "3", "4", "5"])
    }

    @Test("finishes the stream when the child process exits", .timeLimit(.minutes(1)))
    func finishesWhenProcessExits() async {
        // A finite command: the reducing loop can only complete once the stream
        // calls `continuation.finish()`, so the test terminating at all proves it.
        let stream = gateway.runStreaming(executable: "/bin/echo", arguments: ["done"])

        let collected = await stream.reduce(into: [String]()) { $0.append($1) }

        #expect(collected == ["done"])
    }
}
