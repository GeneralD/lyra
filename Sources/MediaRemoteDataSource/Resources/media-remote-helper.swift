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

/// A client's cover as one frame knows it. `pending` is a cover that has not
/// arrived, or whose request failed: the frame repeats the digest it last sent,
/// so the data source keeps the cover it has instead of dropping it for a frame.
enum Cover {
    case image(Data)
    case absent
    case pending
}

/// One client's snapshot, before the frame decides whether to attach its cover.
struct Snapshot {
    let key: String
    let fields: [String: Any]
    let cover: Cover

    var hasTitle: Bool { !((fields["title"] as? String) ?? "").isEmpty }

    func with(cover: Cover) -> Snapshot { Snapshot(key: key, fields: fields, cover: cover) }
}

/// Mirrors `HelperClient.key` on the data-source side: both ends must partition
/// clients identically for the "cover sent once per digest" memo to hold.
func clientKey(bundleID: String?, pid: Int?) -> String {
    bundleID ?? pid.map { "pid:\($0)" } ?? "unknown"
}

/// `JSONSerialization` raises an uncatchable exception on NaN and ±infinity, and
/// every registered client reaches the wire — not only the one the data source
/// will select — so a non-finite value is dropped instead of killing the helper.
func finite(_ value: Any?) -> Double? {
    (value as? Double).flatMap { $0.isFinite ? $0 : nil }
}

func snapshot(bundleID: String?, pid: Int?, info: [String: Any]?, cover: Cover) -> Snapshot {
    let info = info ?? [:]
    let fields: [String: Any?] = [
        "bundle_id": bundleID,
        "pid": pid,
        "title": info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
        "artist": info["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
        "duration": finite(info["kMRMediaRemoteNowPlayingInfoDuration"]),
        "elapsed": finite(info["kMRMediaRemoteNowPlayingInfoElapsedTime"]),
        "rate": finite(info["kMRMediaRemoteNowPlayingInfoPlaybackRate"]),
        // Sent only when MediaRemote reports one: the data source ranks a missing
        // timestamp last and stamps the frame itself for interpolation.
        "timestamp": (info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)?.timeIntervalSinceReferenceDate,
    ]
    return Snapshot(key: clientKey(bundleID: bundleID, pid: pid), fields: fields.compactMapValues { $0 }, cover: cover)
}

/// The system-designated app's snapshot from the global info call.
func legacySnapshot(systemPid: Int?, info: [String: Any]?) -> Snapshot {
    let cover = (info?["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data).map(Cover.image) ?? .absent
    return snapshot(bundleID: nil, pid: systemPid, info: info, cover: cover)
}

func coverDigest(of data: Data) -> String {
    SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
}

/// `JSONSerialization` leaves U+0085, U+2028 and U+2029 unescaped, and the
/// daemon's line reader splits on them too, so a title holding one would cut
/// every frame into pieces. They occur only inside JSON strings, so escaping
/// them keeps the line valid JSON.
func lineSafe(_ json: String) -> String {
    [("\u{85}", "\\u0085"), ("\u{2028}", "\\u2028"), ("\u{2029}", "\\u2029")]
        .reduce(json) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
}

/// Digest of each cover last written, per client. Covers are large (hundreds
/// of KB to MB); base64-streaming them every frame pegged the daemon's CPU
/// (#255), so a cover's bytes go out only when its digest changes. Rebuilt from
/// each emitted frame, exactly as the data source's `ArtworkCache` is.
var sentDigests: [String: String] = [:]

func emit(systemPid: Int?, snapshots: [Snapshot]) {
    let covers = snapshots.map { snapshot -> (digest: String?, payload: Data?) in
        switch snapshot.cover {
        case .image(let data):
            let digest = coverDigest(of: data)
            return (digest, sentDigests[snapshot.key] == digest ? nil : data)
        case .absent:
            return (nil, nil)
        case .pending:
            return (sentDigests[snapshot.key], nil)
        }
    }
    let clients = zip(snapshots, covers).map { snapshot, cover -> [String: Any] in
        let fields: [String: Any?] = [
            "artwork_digest": cover.digest,
            "artwork_base64": cover.payload?.base64EncodedString(),
        ]
        return snapshot.fields.merging(fields.compactMapValues { $0 }) { $1 }
    }
    let frame: [String: Any] = systemPid.map { ["clients": clients, "system_pid": $0] } ?? ["clients": clients]
    guard JSONSerialization.isValidJSONObject(frame),
        let json = try? JSONSerialization.data(withJSONObject: frame)
    else { return }
    print(lineSafe(String(decoding: json, as: UTF8.self)))
    fflush(stdout)
    // Recorded only once the frame is out, so a frame that never left does not
    // mark its covers as delivered.
    sentDigests = Dictionary(
        zip(snapshots, covers).compactMap { snapshot, cover in cover.digest.map { (snapshot.key, $0) } },
        uniquingKeysWith: { _, latest in latest })
}

/// One refresh. A MediaRemote callback that never fires — mediaremoted
/// restarting mid-call, say — must not wedge the helper for good, so a watchdog
/// ends the run; a callback that arrives after that is stale and emits nothing,
/// which keeps frames in order.
final class RefreshRun {
    private(set) var isLive = true
    private let onEnd: () -> Void

    init(timeout: Double, onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { self.end() }
    }

    func end() {
        guard isLive else { return }
        isLive = false
        onEnd()
    }
}

/// Gathers one frame's per-client answers. A client's info fills its slot as
/// soon as it arrives and its cover completes it later, so a slow cover costs
/// the frame that cover, never the client. A client that never answers must not
/// stall the frame either, so a deadline emits whatever has arrived; late
/// answers are dropped. Everything runs on the main queue, so no locking is
/// needed.
final class FrameCollector {
    private let systemPid: Int?
    private let run: RefreshRun
    private var slots: [Snapshot?]
    private var answered: [Bool]
    private var requests: [NSObject] = []  // kept alive until their completions fire
    private var isFinished = false

    init(systemPid: Int?, count: Int, run: RefreshRun) {
        self.systemPid = systemPid
        self.run = run
        self.slots = Array(repeating: nil, count: count)
        self.answered = Array(repeating: false, count: count)
        // Held strongly: if MediaRemote dropped a completion without calling it,
        // nothing else would keep the collector alive and the frame would never
        // be emitted.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.finish() }
    }

    func retain(_ request: NSObject) { requests.append(request) }

    /// Info has arrived and the cover is still on its way.
    func provisional(_ index: Int, with snapshot: Snapshot) {
        guard !isFinished, !answered[index] else { return }
        slots[index] = snapshot
    }

    func fill(_ index: Int, with snapshot: Snapshot) {
        guard !isFinished, !answered[index] else { return }
        slots[index] = snapshot
        answered[index] = true
        guard answered.allSatisfy({ $0 }) else { return }
        finish()
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        requests = []
        let snapshots = slots.compactMap { $0 }
        guard run.isLive else { return }
        // Per-client answers without a single title — the per-client requests
        // failing while the global call still works — must not leave the
        // overlay with less than it had before #358.
        guard !snapshots.contains(where: \.hasTitle) else { return complete(snapshots) }
        getInfo(DispatchQueue.main) { dict in
            let legacy = legacySnapshot(systemPid: self.systemPid, info: dict as? [String: Any])
            self.complete(legacy.hasTitle ? snapshots + [legacy] : snapshots)
        }
    }

    private func complete(_ snapshots: [Snapshot]) {
        guard run.isLive else { return }
        emit(systemPid: systemPid, snapshots: snapshots)
        run.end()
    }
}

/// Pre-#358 path: the system-designated app only, from the global info call.
func legacyRefresh(systemPid: Int?, run: RefreshRun) {
    getInfo(DispatchQueue.main) { dict in
        guard run.isLive else { return }
        emit(systemPid: systemPid, snapshots: [legacySnapshot(systemPid: systemPid, info: dict as? [String: Any])])
        run.end()
    }
}

func clientsRefresh(_ api: ClientAPI, systemPid: Int?, run: RefreshRun) {
    api.getClients(DispatchQueue.main) { array in
        guard run.isLive else { return }
        let clients = ((array as? [AnyObject]) ?? []).compactMap { $0 as? NSObject }
        guard !clients.isEmpty else { return legacyRefresh(systemPid: systemPid, run: run) }
        let collector = FrameCollector(systemPid: systemPid, count: clients.count, run: run)
        for (index, client) in clients.enumerated() {
            query(api, client: client, into: collector, at: index)
        }
    }
}

/// Asks one client for its info and, when it has a title, for its cover.
func query(_ api: ClientAPI, client: NSObject, into collector: FrameCollector, at index: Int) {
    let bundleID =
        client.responds(to: NSSelectorFromString("bundleIdentifier"))
        ? client.value(forKey: "bundleIdentifier") as? String : nil
    let pid =
        (client.responds(to: NSSelectorFromString("processIdentifier"))
        ? (client.value(forKey: "processIdentifier") as? Int) : nil).flatMap { $0 > 0 ? $0 : nil }
    guard let bundleID, let request = api.request(bundleID: bundleID) else {
        return collector.fill(index, with: snapshot(bundleID: bundleID, pid: pid, info: nil, cover: .absent))
    }
    collector.retain(request)
    let onInfo: @convention(block) (NSDictionary?, NSError?) -> Void = { dict, _ in
        let base = snapshot(bundleID: bundleID, pid: pid, info: dict as? [String: Any], cover: .absent)
        // Covers are only worth fetching for clients that can be selected.
        guard base.hasTitle else { return collector.fill(index, with: base) }
        collector.provisional(index, with: base.with(cover: .pending))
        let onArtwork: @convention(block) (AnyObject?, NSError?) -> Void = { artwork, error in
            let object = artwork as? NSObject
            let data =
                object?.responds(to: NSSelectorFromString("imageData")) == true
                ? object?.value(forKey: "imageData") as? Data : nil
            // A failed request says nothing about the cover, so the last one stays.
            let cover = data.map(Cover.image) ?? (error == nil ? .absent : .pending)
            collector.fill(index, with: base.with(cover: cover))
        }
        _ = request.perform(
            ClientAPI.requestArtwork, with: DispatchQueue.main, with: unsafeBitCast(onArtwork, to: AnyObject.self))
    }
    _ = request.perform(ClientAPI.requestInfo, with: DispatchQueue.main, with: unsafeBitCast(onInfo, to: AnyObject.self))
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
    // Longer than the collector's deadline, so it only ends runs whose
    // list or PID call never answered.
    let run = RefreshRun(timeout: 5) {
        isRefreshing = false
        guard isRefreshPending else { return }
        isRefreshPending = false
        refresh()
    }
    // MediaRemote reports PID 0 when no app owns the now-playing session; map it
    // to "absent" so the client never sees a bogus process id.
    let start = { (pid: Int?) in
        guard run.isLive else { return }
        guard let clientAPI else { return legacyRefresh(systemPid: pid, run: run) }
        clientsRefresh(clientAPI, systemPid: pid, run: run)
    }
    guard let getPID else { return start(nil) }
    getPID(DispatchQueue.main) { pid in start(pid > 0 ? Int(pid) : nil) }
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
