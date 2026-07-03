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
    // Stored wrappers capture the dependency context at init, so instances
    // built inside `withDependencies` keep their fakes when methods run
    // outside that scope (the processor task).
    @Dependency(\.configUseCase) private var configService
    @Dependency(\.playbackUseCase) private var playbackService
    @Dependency(\.spectrumUseCase) private var spectrumService
    private let capturingSubject = CurrentValueSubject<Bool, Never>(false)
    private let processor = OSAllocatedUnfairLock(initialState: Task<Void, Never>?.none)

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
        let spectrum = spectrumService
        let subject = capturingSubject
        let playback = playbackService
        // A single for-await loop is the serialization point: events apply
        // one at a time, so a rapid pause→play burst can never interleave
        // capture start/stop calls. `previous` dedupes the helper's periodic
        // ticks — restarting the capture rebuilds the tap, so repeats must
        // not pass.
        let candidate = Task {
            var previous: AudioSourceState?
            for await info in playback.observeNowPlaying() {
                let source = AudioSourceState(
                    pid: info?.pid, isPlaying: (info?.playbackRate ?? 0) > 0)
                guard source != previous else { continue }
                previous = source
                guard let pid = source.pid, source.isPlaying else {
                    await spectrum.stopCapture()
                    subject.send(false)
                    continue
                }
                subject.send(await spectrum.startCapture(pid: pid))
            }
            // Upstream finished (helper EOF): tear the capture down. A
            // cancelled task skips this — stop() owns that teardown, and a
            // start/start race loser must not destroy the winner's capture.
            guard !Task.isCancelled else { return }
            await spectrum.stopCapture()
            subject.send(false)
        }
        let adopted = processor.withLock { task in
            guard task == nil else { return false }
            task = candidate
            return true
        }
        guard adopted else {
            candidate.cancel()
            return
        }
    }

    public func stop() {
        let stopped = processor.withLock { task in
            defer { task = nil }
            return task
        }
        guard let stopped else { return }
        stopped.cancel()
        let spectrum = spectrumService
        let subject = capturingSubject
        Task {
            // Awaiting the cancelled processor first keeps this teardown
            // ordered after its in-flight capture call.
            await stopped.value
            await spectrum.stopCapture()
            subject.send(false)
        }
    }

    public func magnitudes() -> [Float] {
        spectrumService.magnitudes(style: spectrumStyle)
    }
}
