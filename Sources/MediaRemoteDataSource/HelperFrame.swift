import Foundation

/// One line of `media-remote-helper.swift` output: a snapshot of every client
/// registered with MediaRemote, not just the system-designated one (#358).
///
/// MediaRemote's "now playing" slot can be held by an app that is not playing
/// anything (DisplayLink Manager registers a paused, title-less video), which
/// hides the client that actually plays. The helper therefore reports them all
/// and leaves the choice to `NowPlayingClientSelector`.
struct HelperFrame {
    /// PID of the system-designated now-playing app, when MediaRemote names one.
    let systemPid: Int?
    let clients: [HelperClient]
}

/// One now-playing client as reported by the helper. Every field is optional:
/// the helper omits whatever MediaRemote does not report.
struct HelperClient {
    let bundleID: String?
    let pid: Int?
    let title: String?
    let artist: String?
    let duration: Double?
    let elapsed: Double?
    let rate: Double?
    /// Seconds since the reference date, as MediaRemote stamps the snapshot.
    let timestamp: Double?
    /// Content digest of the client's cover; `nil` when it has none.
    let artworkDigest: String?
    /// The cover itself, sent only when its digest changed for this client.
    let artworkBase64: String?
}

extension HelperFrame {
    /// Decodes one helper line; `nil` for anything that is not a frame.
    init?(line: String) {
        guard let frame = try? JSONDecoder().decode(HelperFrame.self, from: Data(line.utf8)) else {
            return nil
        }
        self = frame
    }
}

extension HelperClient {
    /// Identity used to remember the followed client and its cover across frames.
    var key: String {
        bundleID ?? pid.map { "pid:\($0)" } ?? "unknown"
    }
}

extension HelperFrame: Decodable {
    private enum CodingKeys: String, CodingKey {
        case systemPid = "system_pid"
        case clients
    }
}

extension HelperClient: Decodable {
    private enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case pid, title, artist, duration, elapsed, rate, timestamp
        case artworkDigest = "artwork_digest"
        case artworkBase64 = "artwork_base64"
    }
}

extension HelperFrame: Equatable {}
extension HelperFrame: Sendable {}
extension HelperClient: Equatable {}
extension HelperClient: Sendable {}
