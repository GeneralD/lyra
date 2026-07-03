#!/usr/bin/env swift
import Foundation

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(path, RTLD_NOW),
    let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
    let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
else { exit(1) }

typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void

let getInfo = unsafeBitCast(sym, to: GetInfoFn.self)
let register = unsafeBitCast(regSym, to: RegisterFn.self)
// The now-playing app's PID lets the client scope per-process work — a
// CoreAudio process tap for the spectrum analyzer (#23) — to exactly the
// audio source. Auxiliary, so it is resolved optionally: a macOS release
// dropping the symbol degrades to pid-less payloads instead of killing the
// whole helper.
let getPID = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID")
    .map { unsafeBitCast($0, to: GetPIDFn.self) }

// Distinguishes a genuine now-playing change (track switch, play/pause, seek —
// delivered via MediaRemote notifications) from a periodic snapshot refresh
// (`tick`). The client uses this to decide whether the artwork field is
// authoritative for the current track. See `MediaRemoteDataSourceImpl`.
enum Event: String {
    case trackChange = "track-change"
    case tick
}

@Sendable func printInfo(event: Event, pid: Int?) {
    getInfo(DispatchQueue.main) { dict in
        guard let d = dict as? [String: Any],
            let title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
            !title.isEmpty
        else {
            print(#"{"has_info":false}"#)
            fflush(stdout)
            return
        }
        var r: [String: Any] = ["has_info": true, "event": event.rawValue]
        r["title"] = d["kMRMediaRemoteNowPlayingInfoTitle"]
        r["artist"] = d["kMRMediaRemoteNowPlayingInfoArtist"]
        r["duration"] = d["kMRMediaRemoteNowPlayingInfoDuration"]
        r["elapsed"] = d["kMRMediaRemoteNowPlayingInfoElapsedTime"]
        r["rate"] = d["kMRMediaRemoteNowPlayingInfoPlaybackRate"]
        r["pid"] = pid
        // MediaRemote sometimes omits the timestamp field; synthesize it from
        // the current fetch moment so the client can always interpolate elapsed
        // between polls (otherwise lyric highlighting would only advance once
        // per polling interval for timestamp-less sources).
        let ts = (d["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date) ?? Date()
        r["timestamp"] = ts.timeIntervalSinceReferenceDate
        // Artwork is large (hundreds of KB–several MB). Base64-encoding it and
        // streaming it over IPC on every periodic `tick` pegged the daemon's CPU
        // for no benefit while the track was unchanged (#255), so it is emitted
        // only on `track-change`; the client reuses the last cover on ticks. A
        // track-change that carries no artwork signals a genuinely cover-less
        // track, so the client clears its cache.
        if event == .trackChange, let art = d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            r["artwork_base64"] = art.base64EncodedString()
        }
        if let json = try? JSONSerialization.data(withJSONObject: r),
            let s = String(data: json, encoding: .utf8)
        {
            print(s)
            fflush(stdout)
        }
    }
}

@Sendable func fetchAndPrint(event: Event) {
    // MediaRemote reports PID 0 when no app owns the now-playing session; map
    // it to "absent" so the client never sees a bogus process id.
    guard let getPID else { return printInfo(event: event, pid: nil) }
    getPID(DispatchQueue.main) { pid in printInfo(event: event, pid: pid > 0 ? Int(pid) : nil) }
}

// Register for notifications (required before any notifications fire)
register(DispatchQueue.main)

// Observe track/playback changes — fetch info on each event
for name in [
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
] {
    NotificationCenter.default.addObserver(
        forName: NSNotification.Name(name), object: nil, queue: .main
    ) { _ in fetchAndPrint(event: .trackChange) }
}

// Periodic fallback for snapshot refresh (rawElapsed/timestamp/playbackRate).
// The client (LyricsPresenter) interpolates elapsed on every DisplayLink tick
// from this snapshot, so 3s polling is sufficient for lyric sync. pause/seek
// is delivered immediately via `kMRMediaRemoteNowPlayingInfoDidChangeNotification`.
// Ticks omit artwork (see fetchAndPrint) — only the lightweight snapshot fields.
Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in fetchAndPrint(event: .tick) }

// Initial fetch — carries artwork so the first frame has a cover.
fetchAndPrint(event: .trackChange)
RunLoop.main.run()
