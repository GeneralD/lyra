import Dependencies
import Domain
import Foundation
import os

/// Live `DeveloperLog` that appends each block to a file. Enabled state and path are
/// resolved once at the wiring site and passed in (the config read lives in the DI
/// registration, keeping this type purpose-agnostic and unit-testable); toggling
/// therefore takes a daemon restart, the intended coarse control for a debug facility.
/// Writing our own file keeps behavior identical across brew service / self-installed
/// LaunchAgent / foreground `lyra daemon`, none of which redirect stdout the same way.
public struct FileDeveloperLog: Sendable {
    public let isEnabled: Bool
    private let path: String
    /// Serializes `record` so overlapping resolutions can't interleave their
    /// `seekToEnd`/`write` and corrupt or reorder trace blocks. Copies of the struct
    /// share the same underlying lock (the single DI instance is what actually runs).
    private let writeLock = OSAllocatedUnfairLock()

    public init(enabled: Bool, path: String) {
        self.isEnabled = enabled
        self.path = path
    }

    /// Resolve a configured path (tilde-expanded) or fall back to
    /// `${XDG_CACHE_HOME:-~/.cache}/lyra/<defaultFilename>`. The default filename is a
    /// parameter so this stays general across sinks; the caller names the file.
    public static func resolvedPath(configured: String?, defaultFilename: String) -> String {
        if let configured, !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (configured as NSString).expandingTildeInPath
        }
        let base =
            ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(NSHomeDirectory())/.cache"
        return "\(base)/lyra/\(defaultFilename)"
    }
}

extension FileDeveloperLog: DeveloperLog {
    public func record(_ text: String) {
        guard isEnabled else { return }
        let block = text.hasSuffix("\n") ? text : text + "\n"
        guard let data = block.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
        writeLock.withLock {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let handle = try? FileHandle(forWritingTo: url) else {
                // File does not exist yet — create it with this first block.
                try? data.write(to: url, options: .atomic)
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
