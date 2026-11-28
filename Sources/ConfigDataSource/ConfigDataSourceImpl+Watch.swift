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
