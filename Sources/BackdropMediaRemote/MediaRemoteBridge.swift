import Foundation

public enum PollResult {
    case info(MediaRemoteInfo)
    case noInfo
    case eof
}

/// Bridges to MediaRemote.framework via a persistent swift interpreter subprocess.
/// Compiled binaries cannot access the private framework directly.
/// A small swift script runs as a long-lived daemon, observing now-playing
/// notifications and writing JSON lines to stdout, which the parent reads via pipe.
public final class MediaRemoteBridge: @unchecked Sendable {
    private let process: Process
    private let reader: FileHandle

    public init() {
        let scriptPath = Self.ensureScript()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", scriptPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        self.process = process
        self.reader = pipe.fileHandleForReading
        try? process.run()
    }

    deinit {
        process.terminate()
    }
}

extension MediaRemoteBridge {
    public func poll() async -> PollResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [reader] in
                guard let line = Self.readLine(from: reader) else {
                    continuation.resume(returning: .eof)
                    return
                }
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["has_info"] as? Bool == true else {
                    continuation.resume(returning: .noInfo)
                    return
                }
                continuation.resume(returning: .info(MediaRemoteInfo(
                    title: json["title"] as? String,
                    artist: json["artist"] as? String,
                    artworkData: (json["artwork_base64"] as? String).flatMap { Data(base64Encoded: $0) },
                    duration: json["duration"] as? TimeInterval,
                    rawElapsed: json["elapsed"] as? TimeInterval,
                    playbackRate: json["rate"] as? Double ?? 1.0,
                    timestamp: (json["timestamp"] as? TimeInterval).map { Date(timeIntervalSinceReferenceDate: $0) }
                )))
            }
        }
    }

    private static func readLine(from handle: FileHandle) -> String? {
        var buffer = Data()
        while true {
            let byte = handle.readData(ofLength: 1)
            guard !byte.isEmpty else { return nil }
            guard byte.first != UInt8(ascii: "\n") else { break }
            buffer.append(byte)
        }
        return String(data: buffer, encoding: .utf8)
    }
}

extension MediaRemoteBridge {
    private static func ensureScript() -> String {
        let cacheDir = URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
                ?? "\(NSHomeDirectory())/.cache"
        ).appendingPathComponent("backdrop")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let dest = cacheDir.appendingPathComponent("media-remote-helper.swift").path
        guard let source = Bundle.module.url(forResource: "media-remote-helper", withExtension: "swift") else {
            return dest
        }
        try? FileManager.default.removeItem(atPath: dest)
        try? FileManager.default.copyItem(atPath: source.path, toPath: dest)
        return dest
    }
}

extension PollResult: Sendable {}
