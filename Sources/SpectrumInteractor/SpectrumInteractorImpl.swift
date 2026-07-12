import Combine
import Dependencies
import Domain
import Foundation
import os

/// Drives the spectrum analyzer (#23): follows the now-playing stream and
/// keeps the audio capture scoped to the now-playing app, exposing per-bar
/// magnitudes for the Presenter's DisplayLink tick.
///
/// Capture lifecycle rules:
/// - playing + known pid → (re)start the capture for that pid
/// - paused, pid lost, or session gone → stop the capture (not mute — a dead
///   capture costs zero CPU, per the idle-suspension policy)
/// - pid change (app switch) → the stop/start pair reruns for the new pid
///
/// `@unchecked` only because Combine subjects are not `Sendable`; the
/// `capturingSubject` is the sole shared state and is immutable (`let`).
public final class SpectrumInteractorImpl: @unchecked Sendable {
    /// Processor lifecycle. The `.starting` reservation guarantees at most
    /// one event loop ever runs — a competing `start()` never even creates a
    /// task, so no loser can drive the tap lifecycle before its cancellation
    /// lands. The token lets the reserving call detect that `stop()` cleared
    /// the slot while the task was being created.
    private enum Processor: Sendable {
        case idle
        case starting(UUID)
        case running(Task<Void, Never>)
    }

    // Stored wrappers capture the dependency context at init, so instances
    // built inside `withDependencies` keep their fakes when methods run
    // outside that scope (the processor task).
    @Dependency(\.configUseCase) private var configService
    @Dependency(\.playbackUseCase) private var playbackService
    @Dependency(\.spectrumUseCase) private var spectrumService
    private let capturingSubject = CurrentValueSubject<Bool, Never>(false)
    private let processor = OSAllocatedUnfairLock(initialState: Processor.idle)

    public init() {}
}

extension SpectrumInteractorImpl: SpectrumInteractor {
    public var spectrumStyle: SpectrumStyle {
        configService.appStyle.spectrum
    }

    public var isCapturing: AnyPublisher<Bool, Never> {
        capturingSubject.eraseToAnyPublisher()
    }

    public func start() {
        guard spectrumStyle.enabled else { return }
        let token = UUID()
        let reserved = processor.withLock { state in
            guard case .idle = state else { return false }
            state = .starting(token)
            return true
        }
        guard reserved else { return }
        let spectrum = spectrumService
        let subject = capturingSubject
        let playback = playbackService
        // A single for-await loop is the serialization point: events apply
        // one at a time, so a rapid pause→play burst can never interleave
        // capture start/stop calls. `previous` dedupes the helper's periodic
        // ticks — restarting a live capture rebuilds the tap, so repeats must
        // not pass. A failed tap creation is the exception: it does NOT settle
        // `previous`, so the next identical tick re-enters and retries — up to
        // `maxCaptureAttempts` per source, then it gives up until the source
        // changes. That recovers the transient app-switch race (empty process
        // list / HAL contention) without spinning forever on a permanent
        // denial (pre-14.4 OS, TCC) (#312).
        let candidate = Task {
            let maxCaptureAttempts = 3
            var previous: AudioSourceState?
            var failedAttempts = 0
            for await info in playback.observeNowPlaying() {
                let source = AudioSourceState(
                    pid: info?.pid, isPlaying: (info?.playbackRate ?? 0) > 0)
                let isNewSource = source != previous
                let retrying =
                    !isNewSource
                    && (1..<maxCaptureAttempts).contains(failedAttempts)
                guard isNewSource || retrying else { continue }
                // A new source starts its own retry budget; a retry keeps the
                // running count. A stop is always a new source, so it resets
                // here too.
                failedAttempts = isNewSource ? 0 : failedAttempts
                previous = source
                guard let pid = source.pid, source.isPlaying else {
                    await spectrum.stopCapture()
                    subject.send(false)
                    continue
                }
                let started = await spectrum.startCapture(pid: pid)
                subject.send(started)
                failedAttempts = started ? 0 : failedAttempts + 1
                guard started else {
                    let giveUp = failedAttempts >= maxCaptureAttempts
                    fputs(
                        "lyra: spectrum: startCapture(pid: \(pid)) failed "
                            + "(attempt \(failedAttempts)/\(maxCaptureAttempts)); "
                            + (giveUp
                                ? "giving up until the source changes\n"
                                : "retrying on next now-playing tick\n"),
                        stderr)
                    continue
                }
            }
            // Upstream finished (helper EOF): tear the capture down. A
            // cancelled task skips this — stop() owns that teardown.
            guard !Task.isCancelled else { return }
            await spectrum.stopCapture()
            subject.send(false)
        }
        processor.withLock { state in
            guard case .starting(let current) = state, current == token else {
                // stop() cleared the reservation while the task was being
                // created; the candidate must not drive the tap lifecycle.
                candidate.cancel()
                return
            }
            state = .running(candidate)
        }
    }

    public func stop() {
        let stopped = processor.withLock { state -> Task<Void, Never>? in
            defer { state = .idle }
            guard case .running(let task) = state else { return nil }
            return task
        }
        guard let stopped else { return }
        stopped.cancel()
        let spectrum = spectrumService
        let subject = capturingSubject
        let processor = processor
        Task {
            // Awaiting the cancelled processor first keeps this teardown
            // ordered after its in-flight capture call.
            await stopped.value
            // A restart may have taken ownership while the old processor
            // drained; the new generation owns the tap then, and a stale
            // teardown must not destroy its capture.
            let superseded = processor.withLock { state in
                if case .idle = state { return false }
                return true
            }
            guard !superseded else { return }
            await spectrum.stopCapture()
            subject.send(false)
        }
    }

    public func magnitudes(barCount: Int) -> [Float] {
        spectrumService.magnitudes(style: spectrumStyle, barCount: barCount)
    }
}
