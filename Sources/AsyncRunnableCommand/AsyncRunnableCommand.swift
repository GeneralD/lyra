import ArgumentParser
import Foundation

/// Drop-in replacement for `AsyncParsableCommand` that does not initialize Swift's
/// async runtime on the main thread.
///
/// ## Why this exists
///
/// `@main AsyncParsableCommand` starts Swift's cooperative thread pool and takes
/// ownership of the main thread's execution context. `NSApplication.run()`, which
/// lyra's daemon uses to drive the GUI event loop, **must** own the main thread
/// exclusively — the two are fundamentally incompatible. When both compete for the
/// main thread, `NSApplication` starts but SwiftUI rendering never fires, resulting
/// in a blank overlay window.
///
/// ## How it works
///
/// `RootCommand` conforms to sync `ParsableCommand`, keeping the main thread free.
/// Commands that need `async` conform to this protocol instead of
/// `AsyncParsableCommand`. The sync `run()` bridges to `run() async throws` via
/// `DispatchSemaphore`, running the async work on a cooperative thread pool thread
/// while the calling thread waits. This gives subcommands the same ergonomics as
/// `AsyncParsableCommand` without affecting the main thread's run loop.
public protocol AsyncRunnableCommand: ParsableCommand {
    mutating func run() async throws
}

extension AsyncRunnableCommand {
    public mutating func run() throws {
        let command = UnsafeMutableTransferBox(self)
        let result = UnsafeMutableTransferBox(Result<Void, any Error>.success(()))
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                try await command.wrappedValue.run()
                result.wrappedValue = .success(())
            } catch {
                result.wrappedValue = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        try result.wrappedValue.get()
    }
}

/// Workaround for transferring non-Sendable values across concurrency boundaries.
private final class UnsafeMutableTransferBox<T>: @unchecked Sendable {
    var wrappedValue: T
    init(_ wrappedValue: T) { self.wrappedValue = wrappedValue }
}
