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
final class LiveSignalHandlingBackend: SignalHandlingBackend {
    private let ignoreSignalCall: @MainActor (Int32) -> Void
    private let makeSignalSourceCall: @MainActor (Int32, DispatchQueue) -> any AppSignalSource
    private let terminateProcessCall: @MainActor (Int32) -> Void

    convenience init() {
        self.init(
            ignoreSignal: { signal($0, SIG_IGN) },
            makeSignalSource: {
                LiveAppSignalSource(
                    source: DispatchSource.makeSignalSource(signal: $0, queue: $1)
                )
            },
            terminateProcess: { exit($0) }
        )
    }

    init(
        ignoreSignal: @escaping @MainActor (Int32) -> Void,
        makeSignalSource: @escaping @MainActor (Int32, DispatchQueue) -> any AppSignalSource,
        terminateProcess: @escaping @MainActor (Int32) -> Void
    ) {
        ignoreSignalCall = ignoreSignal
        makeSignalSourceCall = makeSignalSource
        terminateProcessCall = terminateProcess
    }

    func ignoreSignal(_ signalType: Int32) {
        ignoreSignalCall(signalType)
    }

    func makeSignalSource(signal signalType: Int32, queue: DispatchQueue) -> any AppSignalSource {
        makeSignalSourceCall(signalType, queue)
    }

    func terminateProcess(_ status: Int32) {
        terminateProcessCall(status)
    }
}

final class LiveAppSignalSource: AppSignalSource {
    private let installEventHandler: (@escaping () -> Void) -> Void
    private let resumeSource: () -> Void

    convenience init(source: DispatchSourceSignal) {
        self.init(
            installEventHandler: { source.setEventHandler(handler: $0) },
            resume: { source.resume() }
        )
    }

    init(
        installEventHandler: @escaping (@escaping () -> Void) -> Void,
        resume: @escaping () -> Void
    ) {
        self.installEventHandler = installEventHandler
        resumeSource = resume
    }

    func setEventHandler(_ handler: @escaping () -> Void) {
        installEventHandler(handler)
    }

    func resume() {
        resumeSource()
    }
}
