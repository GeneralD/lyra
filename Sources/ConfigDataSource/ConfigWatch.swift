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

/// One live hot-reload watch over the config surface: a **directory tier**
/// (the config directory — so a config file created after daemon start is
/// seen, #329 — or, when it does not exist yet, its nearest existing
/// ancestor, #338) plus a tier of file watches and foreign
/// include-directory watches.
///
/// **Every event re-arms both tiers from disk before notifying.** The file
/// tier must, because an atomic save renames a fresh inode into place and
/// kills the old file fd. The directory tier must for the same reason one
/// level up: a config directory that is deleted — or deleted and re-created
/// behind the watch, which keeps the path but gets a fresh inode — leaves the
/// fd on a dead vnode that never fires again. Re-arming is unconditional
/// rather than guarded by a staleness check, because a path-existence check
/// cannot see that replacement at all (#339 review) and re-resolving costs
/// one `open(2)`. Since every re-arm re-reads the on-disk state, an edited
/// `includes` list, a created config directory, and a replaced one all
/// retarget the watch without waiting for the reload to complete.
///
/// The directory tier is therefore self-healing in both directions: it parks
/// on an ancestor while the config directory is absent, walks down as path
/// components appear, promotes onto the directory (arming the file tier and
/// firing `onChange` as the initial load) once it exists, and demotes back if
/// it is removed — at any point in the session's life, not just at start.
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
            armDirectoryTierLocked()
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

    /// Caller must hold `lock`. Re-resolves the directory tier and swaps in a
    /// fresh fd, so a directory that was deleted, replaced, or has just
    /// appeared is picked up by the same code path with no staleness check to
    /// get wrong.
    ///
    /// The live watch is released only once its replacement is secured. If
    /// nothing on the chain can be opened — `open(2)` failing even for the `/`
    /// the ancestors bottom out on, i.e. fd exhaustion — the current token is
    /// kept instead: it may well still be live, and dropping it would leave
    /// the session with no watch to deliver the event that would retry the arm,
    /// stranding it deaf until a daemon restart. That is precisely the state
    /// #338 exists to remove, and re-arming every event (rather than only on a
    /// vanished directory) would otherwise expose it on every config edit
    /// (#339 review).
    private func armDirectoryTierLocked() {
        guard let armed = freshDirectoryTierLocked() else { return }
        directoryToken?.stop()
        directoryToken = armed.token
        ancestorPath = armed.ancestorPath
    }

    /// Caller must hold `lock`. Opens a fresh watch on the config directory,
    /// or — when it does not exist yet — parks on the nearest watchable
    /// ancestor (#338), reporting which. Touches no state, so a caller can
    /// decide whether the result is worth trading the live watch for.
    private func freshDirectoryTierLocked() -> (token: any ConfigWatchToken, ancestorPath: String?)? {
        let configDir = dataSource.configDir
        if let token = gateway.watch(directory: configDir, onChange: { [weak self] in self?.changed() }) {
            return (token, nil)
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
            return (token, ancestor)
        }
        return nil
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
