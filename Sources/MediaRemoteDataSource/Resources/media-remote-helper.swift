#!/usr/bin/env swift
import CryptoKit
import Foundation

// Reports every client registered with MediaRemote, one JSON frame per line:
//
//   {"system_pid":123,"clients":[{"bundle_id":"…","pid":456,"title":"…", …}]}
//
// MediaRemote's system-designated "now playing" app can be one that plays
// nothing — DisplayLink Manager registers a paused, title-less video and keeps
// refreshing it — which hides the app that actually plays (#358). So the
// helper is a sensor only: it reports all clients and the data source
// (`NowPlayingClientSelector`) decides which one to follow.
//
// Only the private API calls below are made, each with a signature verified on
// macOS 26. A guessed C signature (e.g. `MRMediaRemoteGetNowPlayingInfoForPlayer`)
// crashes the helper, and a crash is EOF: the overlay then gets nothing at all.

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
guard let handle = dlopen(path, RTLD_NOW),
    let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
    let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
else { exit(1) }

typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
typealias GetClientsFn = @convention(c) (DispatchQueue, @escaping (CFArray?) -> Void) -> Void
typealias Init3Fn = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?) -> Unmanaged<AnyObject>?
typealias Init1Fn = @convention(c) (AnyObject, Selector, AnyObject?) -> Unmanaged<AnyObject>?

let getInfo = unsafeBitCast(sym, to: GetInfoFn.self)
let register = unsafeBitCast(regSym, to: RegisterFn.self)
// The system-designated app's PID tells the client which entry macOS itself
// considers active. Auxiliary, so it is resolved optionally: a macOS release
// dropping the symbol degrades to frames without `system_pid`.
let getPID = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID")
    .map { unsafeBitCast($0, to: GetPIDFn.self) }

/// Per-client queries: `MRMediaRemoteGetNowPlayingClients` lists the clients,
/// and an `MRNowPlayingRequest` on an `MRPlayerPath` naming one by bundle id
/// returns that client's info and cover. Resolved optionally — if any piece is
/// missing the helper reports only the system-designated app, as before #358.
struct ClientAPI {
    let getClients: GetClientsFn
    let origin: AnyObject
    let pathClass: NSObject.Type
    let requestClass: NSObject.Type

    static let pathInit = NSSelectorFromString("initWithOrigin:bundleIdentifier:player:")
    static let requestInit = NSSelectorFromString("initWithPlayerPath:")
    static let requestInfo = NSSelectorFromString("requestNowPlayingInfoOnQueue:completion:")
    static let requestArtwork = NSSelectorFromString("requestNowPlayingItemArtworkOnQueue:completion:")

    init?(handle: UnsafeMutableRawPointer) {
        guard let clientsSym = dlsym(handle, "MRMediaRemoteGetNowPlayingClients"),
            let pathClass = NSClassFromString("MRPlayerPath") as? NSObject.Type,
            let requestClass = NSClassFromString("MRNowPlayingRequest") as? NSObject.Type,
            pathClass.instancesRespond(to: Self.pathInit),
            requestClass.instancesRespond(to: Self.requestInit),
            requestClass.instancesRespond(to: Self.requestInfo),
            requestClass.instancesRespond(to: Self.requestArtwork),
            pathClass.responds(to: NSSelectorFromString("localPlayerPath")),
            let local = pathClass.perform(NSSelectorFromString("localPlayerPath"))?.takeUnretainedValue()
                as? NSObject,
            local.responds(to: NSSelectorFromString("origin")),
            let origin = local.value(forKey: "origin") as AnyObject?
        else { return nil }
        self.getClients = unsafeBitCast(clientsSym, to: GetClientsFn.self)
        self.origin = origin
        self.pathClass = pathClass
        self.requestClass = requestClass
    }

    /// A request scoped to one client. `alloc`'s +1 is consumed by `init`, whose
    /// +1 result is adopted, so nothing leaks over the helper's lifetime.
    func request(bundleID: String) -> NSObject? {
        guard
            let path = initialized(
                pathClass, Self.pathInit,
                { (imp: Init3Fn, object) in
                    imp(object, Self.pathInit, origin, bundleID as NSString, nil)
                }),
            let request = initialized(
                requestClass, Self.requestInit,
                { (imp: Init1Fn, object) in
                    imp(object, Self.requestInit, path)
                })
        else { return nil }
        return request as? NSObject
    }

    private func initialized<Fn>(
        _ type: NSObject.Type, _ selector: Selector, _ call: (Fn, AnyObject) -> Unmanaged<AnyObject>?
    ) -> AnyObject? {
        guard let allocated = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
            let imp = (allocated as? NSObject)?.method(for: selector)
        else { return nil }
        return call(unsafeBitCast(imp, to: Fn.self), allocated)?.takeRetainedValue()
    }
}

/// One client's snapshot, before the frame decides whether to attach its cover.
struct Snapshot {
    let key: String
    let fields: [String: Any]
    let artwork: Data?
}

/// Mirrors `HelperClient.key` on the data-source side: both ends must partition
/// clients identically for the "cover sent once per digest" memo to hold.
func clientKey(bundleID: String?, pid: Int?) -> String {
    bundleID ?? pid.map { "pid:\($0)" } ?? "unknown"
}

func snapshot(bundleID: String?, pid: Int?, info: [String: Any]?, artwork: Data?) -> Snapshot {
    let info = info ?? [:]
    // MediaRemote sometimes omits the timestamp; synthesize it from the fetch
    // moment so the client can always interpolate elapsed between frames.
    let timestamp = (info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date) ?? Date()
    let fields: [String: Any?] = [
        "bundle_id": bundleID,
        "pid": pid,
        "title": info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
        "artist": info["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
        "duration": info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double,
        "elapsed": info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double,
        "rate": info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double,
        "timestamp": timestamp.timeIntervalSinceReferenceDate,
    ]
    return Snapshot(key: clientKey(bundleID: bundleID, pid: pid), fields: fields.compactMapValues { $0 }, artwork: artwork)
}

func hasTitle(_ info: [String: Any]?) -> Bool {
    !((info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String) ?? "").isEmpty
}

/// Digest of each cover last written, per client. Covers are large (hundreds
/// of KB to MB); base64-streaming them every frame pegged the daemon's CPU
/// (#255), so a cover's bytes go out only when its digest changes. Rebuilt from
/// each emitted frame, exactly as the data source's `ArtworkCache` is.
var sentDigests: [String: String] = [:]

func emit(systemPid: Int?, snapshots: [Snapshot]) {
    let digests = snapshots.reduce(into: [String: String]()) { digests, snapshot in
        digests[snapshot.key] = snapshot.artwork.map {
            SHA256.hash(data: $0).prefix(8).map { String(format: "%02x", $0) }.joined()
        }
    }
    let clients = snapshots.map { snapshot -> [String: Any] in
        guard let digest = digests[snapshot.key], let artwork = snapshot.artwork else { return snapshot.fields }
        let cover: [String: Any] =
            sentDigests[snapshot.key] == digest
            ? ["artwork_digest": digest]
            : ["artwork_digest": digest, "artwork_base64": artwork.base64EncodedString()]
        return snapshot.fields.merging(cover) { $1 }
    }
    sentDigests = digests
    let frame: [String: Any] = systemPid.map { ["clients": clients, "system_pid": $0] } ?? ["clients": clients]
    guard let json = try? JSONSerialization.data(withJSONObject: frame) else { return }
    print(String(decoding: json, as: UTF8.self))
    fflush(stdout)
}

/// Gathers one frame's per-client answers. A client that never answers must not
/// stall the frame, so a deadline emits whatever has arrived; late answers are
/// dropped. Everything runs on the main queue, so no locking is needed.
final class FrameCollector {
    private let systemPid: Int?
    private var slots: [Snapshot?]
    private var remaining: Int
    private var requests: [NSObject] = []  // kept alive until their completions fire
    private var isFinished = false
    private let onFinish: () -> Void

    init(systemPid: Int?, count: Int, onFinish: @escaping () -> Void) {
        self.systemPid = systemPid
        self.slots = Array(repeating: nil, count: count)
        self.remaining = count
        self.onFinish = onFinish
        // Held strongly: if MediaRemote dropped a completion without calling it,
        // nothing else would keep the collector alive, the frame would never be
        // emitted, and `refresh()` would stay blocked for good.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.finish() }
    }

    func retain(_ request: NSObject) { requests.append(request) }

    func fill(_ index: Int, with snapshot: Snapshot) {
        guard !isFinished else { return }
        slots[index] = snapshot
        remaining -= 1
        guard remaining <= 0 else { return }
        finish()
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        requests = []
        emit(systemPid: systemPid, snapshots: slots.compactMap { $0 })
        onFinish()
    }
}

/// Pre-#358 path: the system-designated app only, from the global info call.
func legacyRefresh(systemPid: Int?, done: @escaping () -> Void) {
    getInfo(DispatchQueue.main) { dict in
        let info = dict as? [String: Any]
        let artwork = info?["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        emit(systemPid: systemPid, snapshots: [snapshot(bundleID: nil, pid: systemPid, info: info, artwork: artwork)])
        done()
    }
}

func clientsRefresh(_ api: ClientAPI, systemPid: Int?, done: @escaping () -> Void) {
    api.getClients(DispatchQueue.main) { array in
        let clients = ((array as? [AnyObject]) ?? []).compactMap { $0 as? NSObject }
        guard !clients.isEmpty else { return legacyRefresh(systemPid: systemPid, done: done) }
        let collector = FrameCollector(systemPid: systemPid, count: clients.count, onFinish: done)
        for (index, client) in clients.enumerated() {
            let bundleID =
                client.responds(to: NSSelectorFromString("bundleIdentifier"))
                ? client.value(forKey: "bundleIdentifier") as? String : nil
            let pid =
                (client.responds(to: NSSelectorFromString("processIdentifier"))
                ? (client.value(forKey: "processIdentifier") as? Int) : nil).flatMap { $0 > 0 ? $0 : nil }
            guard let bundleID, let request = api.request(bundleID: bundleID) else {
                collector.fill(index, with: snapshot(bundleID: bundleID, pid: pid, info: nil, artwork: nil))
                continue
            }
            collector.retain(request)
            let onInfo: @convention(block) (NSDictionary?, NSError?) -> Void = { dict, _ in
                let info = dict as? [String: Any]
                guard hasTitle(info) else {
                    return collector.fill(index, with: snapshot(bundleID: bundleID, pid: pid, info: info, artwork: nil))
                }
                // Covers are only worth fetching for clients that can be selected.
                let onArtwork: @convention(block) (AnyObject?, NSError?) -> Void = { artwork, _ in
                    let object = artwork as? NSObject
                    let data =
                        object?.responds(to: NSSelectorFromString("imageData")) == true
                        ? object?.value(forKey: "imageData") as? Data : nil
                    collector.fill(index, with: snapshot(bundleID: bundleID, pid: pid, info: info, artwork: data))
                }
                _ = request.perform(
                    ClientAPI.requestArtwork, with: DispatchQueue.main, with: unsafeBitCast(onArtwork, to: AnyObject.self))
            }
            _ = request.perform(ClientAPI.requestInfo, with: DispatchQueue.main, with: unsafeBitCast(onInfo, to: AnyObject.self))
        }
    }
}

let clientAPI = ClientAPI(handle: handle)

/// Notifications arrive in bursts (several per track change) on top of the
/// periodic tick, so overlapping refreshes are coalesced into one follow-up
/// run instead of racing frames out of order.
var isRefreshing = false
var isRefreshPending = false

func refresh() {
    guard !isRefreshing else {
        isRefreshPending = true
        return
    }
    isRefreshing = true
    let done = {
        isRefreshing = false
        guard isRefreshPending else { return }
        isRefreshPending = false
        refresh()
    }
    // MediaRemote reports PID 0 when no app owns the now-playing session; map it
    // to "absent" so the client never sees a bogus process id.
    let run = { (pid: Int?) in
        guard let clientAPI else { return legacyRefresh(systemPid: pid, done: done) }
        clientsRefresh(clientAPI, systemPid: pid, done: done)
    }
    guard let getPID else { return run(nil) }
    getPID(DispatchQueue.main) { pid in run(pid > 0 ? Int(pid) : nil) }
}

// Register for notifications (required before any notifications fire)
register(DispatchQueue.main)

// `PlayerNowPlayingInfoDidChange` also fires for clients that are not
// system-designated (verified on macOS 26), so a track change in a hidden
// player is reported without waiting for the tick (#358).
for name in [
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    "kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification",
] {
    NotificationCenter.default.addObserver(
        forName: NSNotification.Name(name), object: nil, queue: .main
    ) { _ in refresh() }
}

// Periodic fallback for snapshot refresh (rawElapsed/timestamp/playbackRate).
// The client (LyricsPresenter) interpolates elapsed on every DisplayLink tick
// from this snapshot, so 3s polling is sufficient for lyric sync.
Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in refresh() }

refresh()
RunLoop.main.run()
