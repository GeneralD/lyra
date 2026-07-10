import CoreAudio
import Dependencies

/// CoreAudio process objects for `pid` and every descendant process. The
/// now-playing pid alone is not enough: browsers (Chromium-based) emit audio
/// from a helper subprocess, so a tap scoped to the main pid captures
/// silence. Covering the whole subtree taps whichever family member actually
/// owns the audio stream. Both CoreAudio reads go through the injected
/// `AudioTapGateway` (#310) so this filtering logic is testable with a fake
/// process list, without live audio hardware.
@available(macOS 14.4, *)
func processObjects(forSubtreeOf pid: Int) -> [AudioObjectID] {
    @Dependency(\.audioTapGateway) var gateway
    return gateway.processObjects()
        .filter { isInSubtree(gateway.processPid(of: $0), root: pid_t(pid)) }
}

/// Whether `pid` is in `root`'s process subtree. The subtree walk is the pure
/// `isInProcessSubtree`; only the ppid lookup is the OS boundary.
private func isInSubtree(_ pid: pid_t?, root: pid_t) -> Bool {
    isInProcessSubtree(pid, root: root, parent: parentPid)
}

/// The parent pid of `pid` via `proc_pidinfo`, or `nil` when unreadable.
/// Needs no audio hardware or TCC permission, so it's callable against any
/// real pid (e.g. `getpid()`) without going through the process-object
/// subtree walk.
func parentPid(of pid: pid_t) -> pid_t? {
    var info = proc_bsdinfo()
    let read = proc_pidinfo(
        pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    guard read == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
    return pid_t(info.pbi_ppid)
}

/// Whether `pid` equals `root` or has `root` among its ancestors, walking the
/// parent chain via `parent`. Pure given the ancestry lookup — the live caller
/// backs `parent` with `proc_pidinfo`.
func isInProcessSubtree(_ pid: pid_t?, root: pid_t, parent: (pid_t) -> pid_t?) -> Bool {
    guard var current = pid else { return false }
    while current > 1 {
        guard current != root else { return true }
        guard let up = parent(current) else { return false }
        current = up
    }
    return false
}
