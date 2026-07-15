import Dependencies
import Domain
import Foundation

/// Live `LyricsResolutionLog` that appends the trace to a file. Enabled state and
/// path are read once from `[log]` at construction (mirroring
/// `CustomScriptLyricsDataSourceImpl`); toggling the trace therefore takes a daemon
/// restart, which is the intended coarse control for a debug facility. Writing our
/// own file keeps behavior identical across brew service / self-installed LaunchAgent
/// / foreground `lyra daemon`, none of which redirect stdout the same way.
public struct FileLyricsResolutionLog: Sendable {
    public let isEnabled: Bool
    private let path: String

    public init() {
        @Dependency(\.configDataSource) var configDataSource
        let log = configDataSource.load()?.config.log
        self.init(
            enabled: log?.lyricsResolution ?? false,
            path: Self.resolvedPath(configured: log?.file))
    }

    init(enabled: Bool, path: String) {
        self.isEnabled = enabled
        self.path = path
    }

    static func resolvedPath(configured: String?) -> String {
        if let configured, !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (configured as NSString).expandingTildeInPath
        }
        let base =
            ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(NSHomeDirectory())/.cache"
        return "\(base)/lyra/lyrics-debug.log"
    }
}

extension FileLyricsResolutionLog: LyricsResolutionLog {
    public func record(_ text: String) {
        guard isEnabled else { return }
        let block = text.hasSuffix("\n") ? text : text + "\n"
        guard let data = block.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
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
