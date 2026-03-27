// Copyright (C) 2026 GeneralD (yumejustice@gmail.com)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Domain
import Files
import Foundation

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

extension MediaRemoteBridge: MediaRemoteDataSource {
    public func poll() async -> MediaRemotePollResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [reader] in
                guard let line = Self.readLine(from: reader) else {
                    continuation.resume(returning: .eof)
                    return
                }
                guard let data = line.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    json["has_info"] as? Bool == true
                else {
                    continuation.resume(returning: .noInfo)
                    return
                }
                continuation.resume(
                    returning: .info(
                        NowPlaying(
                            title: json["title"] as? String,
                            artist: json["artist"] as? String,
                            artworkData: (json["artwork_base64"] as? String).flatMap { Data(base64Encoded: $0) },
                            duration: json["duration"] as? TimeInterval,
                            rawElapsed: json["elapsed"] as? TimeInterval,
                            playbackRate: json["rate"] as? Double ?? 1.0,
                            timestamp: (json["timestamp"] as? TimeInterval).map {
                                Date(timeIntervalSinceReferenceDate: $0)
                            }
                        )))
            }
        }
    }
}

extension MediaRemoteBridge {
    fileprivate static func ensureScript() -> String {
        let scriptName = "media-remote-helper.swift"
        let envCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let cachePath =
            (envCache?.isEmpty == false) ? envCache! : "\(Folder.home.path).cache"
        let lyraCachePath = "\(cachePath)/lyra"
        try? FileManager.default.createDirectory(atPath: lyraCachePath, withIntermediateDirectories: true)
        guard let lyraFolder = try? Folder(path: lyraCachePath) else {
            return "\(lyraCachePath)/\(scriptName)"
        }

        let destFile = try? lyraFolder.createFileIfNeeded(withName: scriptName)
        let destPath = destFile?.path ?? "\(lyraCachePath)/\(scriptName)"
        guard let source = Bundle.module.url(forResource: "media-remote-helper", withExtension: "swift") else {
            return destPath
        }
        try? FileManager.default.removeItem(atPath: destPath)
        try? FileManager.default.copyItem(atPath: source.path, toPath: destPath)
        return destPath
    }

    fileprivate static func readLine(from handle: FileHandle) -> String? {
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