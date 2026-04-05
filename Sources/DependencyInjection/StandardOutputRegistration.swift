import Dependencies
import Domain

extension StandardOutputKey: DependencyKey {
    public static let liveValue: any StandardOutput = PrintStandardOutput()
}

private struct PrintStandardOutput: StandardOutput {
    func write(_ message: String) { print(message) }

    // MARK: - Process

    func output(_ result: StartSuccess) {
        switch result {
        case .started(let pid): write("Overlay started (PID \(pid))")
        }
    }

    func output(_ error: StartFailure) {
        switch error {
        case .alreadyRunning: write("Already running")
        case .daemonExitedImmediately: write("Failed to start (daemon exited immediately)")
        case .spawnFailed(let detail): write("Failed to start: \(detail)")
        }
    }

    func output(_ result: StopSuccess) {
        switch result {
        case .stopped: write("Stopped")
        case .notRunning: write("Not running")
        }
    }

    func output(_ error: StopFailure) {
        switch error {
        case .lockReleaseTimedOut: write("Stopped (warning: lock release timed out)")
        }
    }

    // MARK: - Service

    func output(_ result: ServiceInstallSuccess) {
        switch result {
        case .installed(let path): write("Installed and started: \(path)")
        }
    }

    func output(_ error: ServiceInstallFailure) {
        switch error {
        case .managedByHomebrew: write("Already managed by brew services. Run 'brew services stop lyra' first.")
        case .bootstrapFailed(let status): write("Bootstrap failed (status \(status))")
        case .failed(let detail): write("Install failed: \(detail)")
        }
    }

    func output(_ result: ServiceUninstallSuccess) {
        switch result {
        case .uninstalled: write("Uninstalled")
        }
    }

    func output(_ error: ServiceUninstallFailure) {
        switch error {
        case .managedByHomebrew: write("Managed by brew services. Run 'brew services stop lyra' instead.")
        case .notInstalled: write("Not installed")
        case .failed(let detail): write("Uninstall failed: \(detail)")
        }
    }

    // MARK: - Config

    func output(_ result: ConfigWriteSuccess) {
        switch result {
        case .created(let path): write("Config file created at \(path)")
        }
    }

    func output(_ result: ConfigPathSuccess) {
        switch result {
        case .found(let path): write(path)
        }
    }

    func output(_ error: ConfigFailure) {
        switch error {
        case .failed(let detail): write("Config error: \(detail)")
        }
    }
}
