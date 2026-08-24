import Darwin.POSIX
import Domain

/// Live `ErrorLog`: one line per report on stderr, which is where all four call sites
/// were already writing by hand before #345. stderr rather than a file because these
/// are always-on operational errors — the daemon's stderr is captured by whichever
/// supervisor started it (brew service, LaunchAgent, or a foreground `lyra daemon`),
/// so the report lands wherever the user is already looking.
public struct StandardErrorLog: Sendable {
    private let printer: @Sendable (String) -> Void

    public init() {
        self.init { fputs($0, stderr) }
    }

    /// Test seam, mirroring `PrintStandardOutput`'s injected printers: the rendering is
    /// the part worth asserting on, and it is not observable through a real `fputs`.
    init(printer: @escaping @Sendable (String) -> Void) {
        self.printer = printer
    }
}

extension StandardErrorLog: ErrorLog {
    public func record(_ subsystem: ErrorSubsystem, _ message: String) {
        printer("lyra: \(subsystem.rawValue) \(message)\n")
    }
}
