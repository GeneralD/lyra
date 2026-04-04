import ArgumentParser
import Foundation
import Testing

@testable import AsyncRunnableCommand

/// Shared actor for observing side effects from async commands.
private actor Witness {
    var called = false
    var value = 0
    var threadLabel = ""

    func markCalled() { called = true }
    func set(_ v: Int) { value = v }
    func setThread(_ label: String) { threadLabel = label }
}

/// Global witnesses keyed by test, avoiding Decodable conformance issues.
private enum Witnesses {
    nonisolated(unsafe) static var current = Witness()
}

@Suite("AsyncRunnableCommand", .serialized)
struct AsyncRunnableCommandSpec {
    init() { Witnesses.current = Witness() }

    // MARK: - Normal Behavior

    @Suite("bridges async run to sync ParsableCommand", .serialized)
    struct Bridge {
        @Test("sync run() calls async run() and completes")
        func syncsToAsync() async throws {
            Witnesses.current = Witness()
            var command = SucceedingCommand()
            try runSync(&command)
            #expect(await Witnesses.current.called)
        }

        @Test("returns value computed in async context")
        func asyncResult() async throws {
            Witnesses.current = Witness()
            var command = ValueCommand()
            try runSync(&command)
            #expect(await Witnesses.current.value == 42)
        }
    }

    // MARK: - Error Propagation

    @Suite("propagates errors from async run")
    struct ErrorPropagation {
        @Test("throws ExitCode from async run")
        func exitCode() {
            var command = FailingCommand()
            #expect(throws: ExitCode.failure) {
                try runSync(&command)
            }
        }

        @Test("throws custom error from async run")
        func customError() {
            var command = CustomErrorCommand()
            #expect(throws: CustomErrorCommand.SomeError.self) {
                try runSync(&command)
            }
        }
    }

    // MARK: - Async Features

    @Suite("supports async operations", .serialized)
    struct AsyncFeatures {
        @Test("awaits Task.sleep without blocking cooperative thread pool")
        func taskSleep() async throws {
            Witnesses.current = Witness()
            var command = SleepingCommand()
            try runSync(&command)
            #expect(await Witnesses.current.called)
        }

        @Test("concurrent tasks within async run complete correctly")
        func concurrentTasks() async throws {
            Witnesses.current = Witness()
            var command = ConcurrentCommand()
            try runSync(&command)
            #expect(await Witnesses.current.value == 10)
        }
    }

    // MARK: - Thread Safety

    @Suite("thread behavior", .serialized)
    struct ThreadBehavior {
        @Test("async run executes off the main dispatch queue")
        func runsOffMain() async throws {
            Witnesses.current = Witness()
            var command = ThreadCheckCommand()
            try runSync(&command)
            #expect(await Witnesses.current.threadLabel != "com.apple.main-thread")
        }
    }
}

// MARK: - Helpers

/// Explicitly call the sync `run() throws` (the bridging default implementation).
private func runSync<C: AsyncRunnableCommand>(_ command: inout C) throws {
    try command.run() as Void
}

// MARK: - Test Commands

private struct SucceedingCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(commandName: "succeed")

    mutating func run() async throws {
        await Witnesses.current.markCalled()
    }
}

private struct ValueCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(commandName: "value")

    mutating func run() async throws {
        let v = await Task { 42 }.value
        await Witnesses.current.set(v)
    }
}

private struct FailingCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(commandName: "fail")

    mutating func run() async throws {
        throw ExitCode.failure
    }
}

private struct CustomErrorCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(commandName: "custom-error")
    enum SomeError: Error { case oops }

    mutating func run() async throws {
        throw SomeError.oops
    }
}

private struct SleepingCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(commandName: "sleep")

    mutating func run() async throws {
        try await Task.sleep(for: .milliseconds(10))
        await Witnesses.current.markCalled()
    }
}

private struct ConcurrentCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(commandName: "concurrent")

    mutating func run() async throws {
        let sum = await withTaskGroup(of: Int.self, returning: Int.self) { group in
            for i in 1...4 { group.addTask { i } }
            return await group.reduce(0, +)
        }
        await Witnesses.current.set(sum)
    }
}

private struct ThreadCheckCommand: AsyncRunnableCommand {
    static let configuration = CommandConfiguration(commandName: "thread")

    mutating func run() async throws {
        let label = String(cString: __dispatch_queue_get_label(nil))
        await Witnesses.current.setThread(label)
    }
}
