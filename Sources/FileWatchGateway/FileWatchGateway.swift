import Darwin
import Dispatch
import Domain

/// Live `ConfigWatchGateway`: watches a directory's file descriptor via
/// `DispatchSource.makeFileSystemObjectSource`, mirroring the
/// `CoreAudioTapGateway`/`DarwinGateway` shape (Domain contract + dedicated
/// Support module implementation). A directory (not the config file itself)
/// is watched because an editor's atomic save renames the file — the old fd
/// is invalidated by the rename, but the parent directory's fd survives and
/// still observes the save.
public struct FileWatchGateway: Sendable {
    public init() {}
}

extension FileWatchGateway: ConfigWatchGateway {
    public func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .global())
        source.setEventHandler { onChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return FileWatchToken(source: source)
    }
}

/// `class` justified by the same shape as `AudioTapGateway`'s handle types:
/// it owns a live `DispatchSourceFileSystemObject` and must cancel it exactly
/// once via `stop()` — reference identity, not a value.
private final class FileWatchToken: ConfigWatchToken, @unchecked Sendable {
    private let source: any DispatchSourceFileSystemObject

    init(source: any DispatchSourceFileSystemObject) {
        self.source = source
    }

    func stop() {
        source.cancel()
    }
}
