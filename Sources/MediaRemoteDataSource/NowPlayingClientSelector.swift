/// Chooses which now-playing client to follow from one helper frame (#358).
///
/// Only clients with a title are candidates — a title-less client such as
/// DisplayLink Manager's paused video can hold the system slot but has nothing
/// to show. Among candidates, the first difference in this order wins:
///
/// 1. playing (a missing rate counts as playing, as `NowPlaying` assumes 1x)
/// 2. the system-designated client, so macOS's own "most recently active"
///    judgement decides between two apps that both play
/// 3. the client followed last time, so selection does not flap
/// 4. the newer snapshot timestamp
/// 5. the smaller key, so the result never depends on the helper's ordering
struct NowPlayingClientSelector {}

extension NowPlayingClientSelector {
    func selection(in frame: HelperFrame, following followedKey: String?) -> HelperClient? {
        frame.clients
            .filter { !($0.title ?? "").isEmpty }
            .map { (client: $0, rank: rank(of: $0, in: frame, following: followedKey)) }
            .max { $0.rank < $1.rank }?
            .client
    }

    private func rank(of client: HelperClient, in frame: HelperFrame, following followedKey: String?) -> Rank {
        Rank(
            isPlaying: (client.rate ?? 1.0) > 0,
            isSystem: client.pid != nil && client.pid == frame.systemPid,
            isFollowed: client.key == followedKey,
            timestamp: client.timestamp ?? -.infinity,
            key: client.key
        )
    }
}

extension NowPlayingClientSelector {
    /// Lexicographic preference; a greater rank is the better client.
    private struct Rank: Comparable {
        let isPlaying: Bool
        let isSystem: Bool
        let isFollowed: Bool
        let timestamp: Double
        let key: String

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            let lhsFlags = (lhs.isPlaying ? 1 : 0, lhs.isSystem ? 1 : 0, lhs.isFollowed ? 1 : 0, lhs.timestamp)
            let rhsFlags = (rhs.isPlaying ? 1 : 0, rhs.isSystem ? 1 : 0, rhs.isFollowed ? 1 : 0, rhs.timestamp)
            guard lhsFlags == rhsFlags else { return lhsFlags < rhsFlags }
            // The smaller key is the better one, so it must compare as greater.
            return lhs.key > rhs.key
        }
    }
}
