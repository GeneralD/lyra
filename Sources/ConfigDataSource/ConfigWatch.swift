import Domain
import Files
import Foundation

extension ConfigDataSourceImpl {
    public func watchChanges(onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        ConfigWatchSession(dataSource: self, gateway: watchGateway, onChange: onChange).armed()
    }

    /// Current hot-reload watch targets, resolved from the on-disk TOML — not
    /// from loaded state — so re-arming never depends on a completed reload.
    /// Files: the config file plus its `includes` (a directory watch alone
    /// misses in-place overwrites). Foreign directories: parents of includes
    /// living outside the config directory, whose atomic saves kill the file fd
    /// without firing the config-directory watch. Includes resolve without
    /// requiring the files to exist — a missing include must still get its
    /// parent directory watched so that creating it later fires an event; its
    /// file watch simply fails to arm until then.
    var watchTargets: (files: [String], foreignDirectories: [String]) {
        guard let file = findConfigFile() else { return ([], []) }
        let includes = includedConfigPaths
        let foreignDirectories = Set(includes.compactMap(parentDirectory))
            .subtracting([file.parent?.path].compactMap { $0 })
        return ([file.path] + includes, Array(foreignDirectories))
    }

    /// Parent directory of an include path, Files-normalized when it exists on
    /// disk (collapsing `./`-style segments, trailing slash included) so it
    /// compares consistently against the Files-derived config-directory path.
    /// A parent that does not exist yet keeps its literal form — its directory
    /// watch fails to arm until the directory appears.
    private func parentDirectory(of path: String) -> String? {
        guard let slash = path.lastIndex(of: "/") else { return nil }
        let literal = String(path[...slash])
        return (try? Folder(path: literal))?.path ?? literal
    }
}

/// One live hot-reload watch: a config-directory watch (it survives atomic
/// saves and sees a config file created after daemon start, #329) plus a
/// re-armable tier of file watches and foreign include-directory watches.
/// Every event re-arms the file tier before notifying, because an atomic save
/// renames a fresh inode into place and kills the old file fd; re-arming reads
/// the current on-disk `includes`, so an edited include list retargets the
/// watch without waiting for the reload to complete.
///
/// When the config directory itself does not exist, the directory tier parks
/// on its nearest existing ancestor instead (#338): each ancestor event walks
/// the watch down as path components appear, and only reaching the config
/// directory itself arms the file tier and fires `onChange` as the initial
/// load. A config directory deleted while watched is demoted back onto an
/// ancestor the same way, so the session recovers from the directory coming
/// and going at any point in its life — not just at daemon start.
///
/// `final class`: shared mutable token state behind a lock, plus deinit cleanup
/// so a dropped token cannot leak DispatchSources. `@unchecked Sendable`: all
/// mutable state is accessed under `lock`.
final class ConfigWatchSession: @unchecked Sendable {
    private let lock = NSLock()
    private let dataSource: ConfigDataSourceImpl
    private let gateway: any ConfigWatchGateway
    private let onChange: @Sendable () -> Void
    private var directoryToken: (any ConfigWatchToken)?
    /// Non-nil while the directory tier is parked on an ancestor of a
    /// not-yet-existing config directory (#338); nil once the config
    /// directory itself is watched.
    private var ancestorPath: String?
    private var rearmedTokens: [any ConfigWatchToken] = []
    private var stopped = false

    init(
        dataSource: ConfigDataSourceImpl,
        gateway: any ConfigWatchGateway,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.dataSource = dataSource
        self.gateway = gateway
        self.onChange = onChange
    }

    deinit {
        stop()
    }
}

extension ConfigWatchSession: ConfigWatchToken {
    func stop() {
        lock.withLock {
            stopped = true
            directoryToken?.stop()
            directoryToken = nil
            ancestorPath = nil
            for token in rearmedTokens { token.stop() }
            rearmedTokens = []
        }
    }
}

extension ConfigWatchSession {
    /// Arms both watch tiers, returning self as the caller's stop handle. When
    /// the config directory does not exist yet, the directory tier parks on
    /// its nearest existing ancestor instead (#338) — creating the directory
    /// later promotes the watch onto it and fires the initial load — so nil is
    /// returned only when nothing on the ancestor chain is watchable either.
    func armed() -> ConfigWatchSession? {
        lock.withLock {
            armDirectoryTierLocked()
            guard directoryToken != nil else { return nil }
            rearmFilesLocked()
            return self
        }
    }

    private func changed() {
        let live = lock.withLock {
            guard !stopped else { return false }
            reparkDirectoryTierIfGoneLocked()
            rearmFilesLocked()
            return true
        }
        guard live else { return }
        onChange()
    }

    /// An event beneath the parked ancestor: re-resolve the directory tier
    /// and, only when the config directory itself became watchable, arm the
    /// file tier and fire the initial load (#338). Ancestor churn that does
    /// not materialize the config directory re-parks silently — no reload
    /// fires, so noise at `$HOME` level costs a few syscalls, never a decode;
    /// the promotion ping itself is absorbed by the interactor's debounce
    /// like any other event.
    private func ancestorChanged() {
        let promoted = lock.withLock {
            guard !stopped, ancestorPath != nil else { return false }
            armDirectoryTierLocked()
            guard directoryToken != nil, ancestorPath == nil else { return false }
            rearmFilesLocked()
            return true
        }
        guard promoted else { return }
        onChange()
    }

    /// Caller must hold `lock`. Points the directory tier at the config
    /// directory itself, or — when that cannot be watched because it does not
    /// exist yet — parks it on the nearest watchable ancestor (#338). The
    /// previous token is always released: a re-park onto the same path swaps
    /// in a fresh fd, which also heals a watch whose directory was deleted
    /// and re-created behind the dead descriptor.
    private func armDirectoryTierLocked() {
        directoryToken?.stop()
        directoryToken = nil
        ancestorPath = nil
        let configDir = dataSource.configDir
        if let token = gateway.watch(directory: configDir, onChange: { [weak self] in self?.changed() }) {
            directoryToken = token
            return
        }
        // A plain loop, not `lazy.compactMap { … }.first`: arming a watch is a
        // side effect, and a lazy *collection* transform runs twice for the
        // found element (computing startIndex, then subscripting) — which
        // would arm and leak a duplicate fd.
        for ancestor in directoryAncestors(of: configDir) {
            guard
                let token = gateway.watch(
                    directory: ancestor, onChange: { [weak self] in self?.ancestorChanged() })
            else { continue }
            directoryToken = token
            ancestorPath = ancestor
            return
        }
    }

    /// Caller must hold `lock`. A deleted config directory leaves the
    /// directory tier on a dead fd that will never fire again — re-park it on
    /// the nearest existing ancestor so a later re-creation is caught (#338).
    /// Deletion is detected by existence, not by event kind (the gateway
    /// callback carries none); the per-event file-tier re-arm keeps covering
    /// the files either way.
    private func reparkDirectoryTierIfGoneLocked() {
        guard ancestorPath == nil, (try? Folder(path: dataSource.configDir)) == nil else { return }
        armDirectoryTierLocked()
    }

    /// Caller must hold `lock`.
    private func rearmFilesLocked() {
        for token in rearmedTokens { token.stop() }
        let targets = dataSource.watchTargets
        rearmedTokens =
            targets.files.compactMap { path in
                gateway.watch(file: path) { [weak self] in self?.changed() }
            }
            + targets.foreignDirectories.compactMap { directory in
                gateway.watch(directory: directory) { [weak self] in self?.changed() }
            }
    }
}

/// Successive parent directories of an absolute path, nearest first, ending at
/// "/". Pure string math that never touches the filesystem — the caller
/// decides which ancestor is watchable by trying to arm it.
func directoryAncestors(of path: String) -> [String] {
    let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    guard trimmed.count > 1, let slash = trimmed.lastIndex(of: "/") else { return [] }
    let parent = slash == trimmed.startIndex ? "/" : String(trimmed[..<slash])
    return [parent] + directoryAncestors(of: parent)
}
