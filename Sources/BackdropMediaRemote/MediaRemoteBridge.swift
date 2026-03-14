import Foundation

public final class MediaRemoteBridge: @unchecked Sendable {
    private typealias Fn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    private let function: Fn

    public init?() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW),
              let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else { return nil }
        function = unsafeBitCast(sym, to: Fn.self)
    }

    public func poll() async -> MediaRemoteInfo? {
        await withCheckedContinuation { continuation in
            function(DispatchQueue.main) { dict in
                let info = (dict as? [String: Any]).map(Self.parse)
                continuation.resume(returning: info)
            }
        }
    }

    private static func parse(_ dict: [String: Any]) -> MediaRemoteInfo {
        MediaRemoteInfo(
            title: dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
            artist: dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
            artworkData: dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
            duration: dict["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval,
            rawElapsed: dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval,
            playbackRate: dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 1.0,
            timestamp: dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date
        )
    }
}
