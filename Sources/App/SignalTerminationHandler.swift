import Darwin
import Dispatch

@MainActor
public final class SignalTerminationHandler: TerminationHandling {
    private let signals: [Int32]
    private let backend: any SignalHandlingBackend
    private var signalSources: [any AppSignalSource] = []

    public init(
        signals: [Int32],
        backend: any SignalHandlingBackend
    ) {
        self.signals = signals
        self.backend = backend
    }

    public func install(onTermination: @escaping @MainActor () -> Void) {
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
public protocol SignalHandlingBackend: AnyObject {
    func ignoreSignal(_ signalType: Int32)
    func makeSignalSource(signal signalType: Int32, queue: DispatchQueue) -> any AppSignalSource
    func terminateProcess(_ status: Int32)
}

public protocol AppSignalSource: AnyObject {
    func setEventHandler(_ handler: @escaping () -> Void)
    func resume()
}

@MainActor
public final class LiveSignalHandlingBackend: SignalHandlingBackend {
    private let terminateProcessCall: @MainActor (Int32) -> Void

    public init(terminateProcess: @escaping @MainActor (Int32) -> Void) {
        terminateProcessCall = terminateProcess
    }

    public func ignoreSignal(_ signalType: Int32) {
        signal(signalType, SIG_IGN)
    }

    public func makeSignalSource(signal signalType: Int32, queue: DispatchQueue) -> any AppSignalSource {
        LiveAppSignalSource(source: DispatchSource.makeSignalSource(signal: signalType, queue: queue))
    }

    public func terminateProcess(_ status: Int32) {
        terminateProcessCall(status)
    }
}

final class LiveAppSignalSource: AppSignalSource {
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
