import Darwin
import Dispatch

@MainActor
final class SignalTerminationHandler: TerminationHandling {
    private let signals: [Int32]
    private let backend: any SignalHandlingBackend
    private var signalSources: [any AppSignalSource] = []

    init(
        signals: [Int32] = [SIGTERM, SIGINT],
        backend: any SignalHandlingBackend = LiveSignalHandlingBackend()
    ) {
        self.signals = signals
        self.backend = backend
    }

    func install(onTermination: @escaping @MainActor () -> Void) {
        let backend = backend
        signalSources = signals.map { signalType in
            backend.ignoreSignal(signalType)
            let source = backend.makeSignalSource(signal: signalType, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    onTermination()
                    backend.terminateProcess(0)
                }
            }
            source.resume()
            return source
        }
    }
}

@MainActor
protocol SignalHandlingBackend: AnyObject {
    func ignoreSignal(_ signalType: Int32)
    func makeSignalSource(signal signalType: Int32, queue: DispatchQueue) -> any AppSignalSource
    func terminateProcess(_ status: Int32)
}

protocol AppSignalSource: AnyObject {
    func setEventHandler(_ handler: @escaping () -> Void)
    func resume()
}

@MainActor
private final class LiveSignalHandlingBackend: SignalHandlingBackend {
    func ignoreSignal(_ signalType: Int32) {
        signal(signalType, SIG_IGN)
    }

    func makeSignalSource(signal signalType: Int32, queue: DispatchQueue) -> any AppSignalSource {
        LiveAppSignalSource(source: DispatchSource.makeSignalSource(signal: signalType, queue: queue))
    }

    func terminateProcess(_ status: Int32) {
        exit(status)
    }
}

private final class LiveAppSignalSource: AppSignalSource {
    private let source: DispatchSourceSignal

    init(source: DispatchSourceSignal) {
        self.source = source
    }

    func setEventHandler(_ handler: @escaping () -> Void) {
        source.setEventHandler(handler: handler)
    }

    func resume() {
        source.resume()
    }
}
