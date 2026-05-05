import Darwin
import Dispatch

@MainActor
final class SignalTerminationHandler: TerminationHandling {
    private let signals: [Int32]
    private let terminateProcess: @MainActor (Int32) -> Void
    private var signalSources: [DispatchSourceSignal] = []

    init(
        signals: [Int32] = [SIGTERM, SIGINT],
        terminateProcess: @escaping @MainActor (Int32) -> Void = { exit($0) }
    ) {
        self.signals = signals
        self.terminateProcess = terminateProcess
    }

    func install(onTermination: @escaping @MainActor () -> Void) {
        let terminateProcess = terminateProcess
        signalSources = signals.map { signalType in
            signal(signalType, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalType, queue: .main)
            source.setEventHandler {
                onTermination()
                terminateProcess(0)
            }
            source.resume()
            return source
        }
    }
}
