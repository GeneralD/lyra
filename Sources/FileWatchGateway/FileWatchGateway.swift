import Darwin
import Dispatch
import Domain

/// Live `ConfigWatchGateway`: watches file descriptors via
/// `DispatchSource.makeFileSystemObjectSource`, mirroring the
/// `CoreAudioTapGateway`/`DarwinGateway` shape (Domain contract + dedicated
/// Support module implementation). Two complementary watches are offered
/// because neither alone sees every save style:
/// - the **directory** fd survives an editor's atomic save (the rename
///   invalidates the old file fd but changes the directory entry), yet a
///   directory vnode never fires for an in-place write to a contained file;
/// - the **file** fd observes in-place overwrites (editors that save without
///   renaming, `cp`, appends), but dies on every rename and must be re-armed
///   by the caller after each event.
public struct FileWatchGateway: Sendable {
    public init() {}
}

extension FileWatchGateway: ConfigWatchGateway {
    public func watch(directory: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        watchPath(directory, onChange: onChange)
    }

    public func watch(file: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        watchPath(file, onChange: onChange)
    }

    private func watchPath(_ path: String, onChange: @escaping @Sendable () -> Void) -> (any ConfigWatchToken)? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .global())
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
