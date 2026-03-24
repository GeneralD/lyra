#!/usr/bin/env swift

import Foundation

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(path, RTLD_NOW),
    let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
    let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
else { exit(1) }

typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

let getInfo = unsafeBitCast(sym, to: GetInfoFn.self)
let register = unsafeBitCast(regSym, to: RegisterFn.self)

@Sendable func fetchAndPrint() {
    getInfo(DispatchQueue.main) { dict in
        guard let d = dict as? [String: Any],
            d["kMRMediaRemoteNowPlayingInfoTitle"] != nil
        else {
            print(#"{"has_info":false}"#)
            fflush(stdout)
            return
        }
        var r: [String: Any] = ["has_info": true]
        r["title"] = d["kMRMediaRemoteNowPlayingInfoTitle"]
        r["artist"] = d["kMRMediaRemoteNowPlayingInfoArtist"]
        r["duration"] = d["kMRMediaRemoteNowPlayingInfoDuration"]
        r["elapsed"] = d["kMRMediaRemoteNowPlayingInfoElapsedTime"]
        r["rate"] = d["kMRMediaRemoteNowPlayingInfoPlaybackRate"]
        if let ts = d["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
            r["timestamp"] = ts.timeIntervalSinceReferenceDate
        }
        if let art = d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
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

// Register for notifications (required before any notifications fire)
register(DispatchQueue.main)

// Observe track/playback changes — fetch info on each event
for name in [
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
] {
    NotificationCenter.default.addObserver(
        forName: NSNotification.Name(name), object: nil, queue: .main
    ) { _ in fetchAndPrint() }
}

// Periodic fallback for elapsed time updates (needed for lyric sync)
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in fetchAndPrint() }

// Initial fetch
fetchAndPrint()
RunLoop.main.run()
