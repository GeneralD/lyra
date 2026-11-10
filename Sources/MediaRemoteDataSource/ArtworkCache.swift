import Foundation

/// Decoded covers per now-playing client, keyed by `HelperClient.key` (#358).
///
/// The helper sends a cover's bytes only when its digest changes for that
/// client (#255) and the data source decodes a payload only once (#270), so the
/// cache holds every reported client's cover, not just the followed one:
/// switching clients must not wait for a resend that never comes. The cache
/// mirrors the helper's own memo of what it sent, which is rebuilt from the
/// clients of each emitted frame — hence clients absent from a frame are
/// evicted here too.
struct ArtworkCache {
    private let entries: [String: Entry]

    init() {
        self.init(entries: [:])
    }

    private init(entries: [String: Entry]) {
        self.entries = entries
    }
}

extension ArtworkCache {
    /// The cache after one frame: unchanged digests keep their decoded cover,
    /// changed ones decode the payload that accompanies them, and clients that
    /// report no digest (or are absent) drop theirs.
    func updated(by clients: [HelperClient], decode: (String) -> Data?) -> ArtworkCache {
        ArtworkCache(
            entries: Dictionary(
                clients.compactMap { client in entry(for: client, decode: decode).map { (client.key, $0) } },
                uniquingKeysWith: { _, latest in latest }))
    }

    func artwork(for key: String) -> Data? {
        entries[key]?.data
    }

    /// A client's entry after this frame. A changed digest without its payload
    /// yields no entry rather than the stale cover.
    private func entry(for client: HelperClient, decode: (String) -> Data?) -> Entry? {
        guard let digest = client.artworkDigest else { return nil }
        guard let cached = entries[client.key], cached.digest == digest else {
            return client.artworkBase64.map { Entry(digest: digest, data: decode($0)) }
        }
        return cached
    }
}

extension ArtworkCache {
    private struct Entry {
        let digest: String
        let data: Data?
    }
}
