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

/// One live hot-reload watch: a config-directory watch armed once (it survives
/// atomic saves and sees a config file created after daemon start, #329) plus a
/// re-armable tier of file watches and foreign include-directory watches.
/// Every event re-arms the file tier before notifying, because an atomic save
/// renames a fresh inode into place and kills the old file fd; re-arming reads
/// the current on-disk `includes`, so an edited include list retargets the
/// watch without waiting for the reload to complete.
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
            for token in rearmedTokens { token.stop() }
            rearmedTokens = []
        }
    }
}

extension ConfigWatchSession {
    /// Arms both watch tiers, returning self as the caller's stop handle — or
    /// nil when the config directory itself cannot be watched (it does not
    /// exist yet), in which case nothing else is watchable either.
    func armed() -> ConfigWatchSession? {
        lock.withLock {
            directoryToken = gateway.watch(directory: dataSource.configDir) { [weak self] in self?.changed() }
            guard directoryToken != nil else { return nil }
            rearmFilesLocked()
            return self
        }
    }

    private func changed() {
        let live = lock.withLock {
            guard !stopped else { return false }
            rearmFilesLocked()
            return true
        }
        guard live else { return }
        onChange()
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
