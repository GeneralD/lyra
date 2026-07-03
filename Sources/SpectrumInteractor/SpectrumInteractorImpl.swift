import Combine
import Dependencies
import Domain
import Foundation
import FrequencyAnalyzer
import os

/// Drives the spectrum analyzer (#23): follows `TrackInteractor.audioSource`,
/// keeps the CoreAudio process tap scoped to the now-playing app, and converts
/// the captured PCM window into per-bar magnitudes on demand.
///
/// Tap lifecycle rules:
/// - playing + known pid → (re)create the tap for that pid
/// - paused, pid lost, or session gone → destroy the tap (not mute — a dead
///   tap costs zero CPU, per the idle-suspension policy)
/// - pid change (app switch) → the destroy/create pair reruns for the new pid
///
/// `@unchecked` only because of the lazy `analyzer`, which is touched solely
/// from the main-thread DisplayLink tick via `magnitudes()`.
public final class SpectrumInteractorImpl: @unchecked Sendable {
    private struct Pipeline {
        var cancellable: AnyCancellable?
        var processor: Task<Void, Never>?
        var continuation: AsyncStream<AudioSourceState>.Continuation?
    }

    // Stored wrappers capture the dependency context at init, so instances
    // built inside `withDependencies` keep their fakes when methods run
    // outside that scope (sinks, the processor task).
    @Dependency(\.configUseCase) private var configService
    @Dependency(\.trackInteractor) private var trackInteractor
    @Dependency(\.audioTapDataSource) private var tap
    private let capturingSubject = CurrentValueSubject<Bool, Never>(false)
    private let pipeline = OSAllocatedUnfairLock(uncheckedState: Pipeline())
    private lazy var analyzer = FrequencyAnalyzer(
        fftSize: spectrumStyle.fftSize,
        barCount: spectrumStyle.barCount,
        minDb: spectrumStyle.minDb,
        maxDb: spectrumStyle.maxDb
    )

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
        let tap = tap
        let subject = capturingSubject
        // The stream is the serialization point: audio-source events queue up
        // and the single processor task applies them one at a time, so a rapid
        // pause→play→pause burst can never interleave tap create/destroy calls.
        let (stream, continuation) = AsyncStream<AudioSourceState>.makeStream()
        let processor = Task {
            for await source in stream {
                guard let pid = source.pid, source.isPlaying else {
                    await tap.stopTap()
                    subject.send(false)
                    continue
                }
                subject.send(await tap.startTap(pid: pid))
            }
            // Stream finished (stop()): tear the tap down after the last event.
            guard !Task.isCancelled else { return }
            await tap.stopTap()
            subject.send(false)
        }
        let cancellable = trackInteractor.audioSource
            .sink { continuation.yield($0) }
        let adopted = pipeline.withLockUnchecked { state in
            guard state.cancellable == nil else { return false }
            state = Pipeline(
                cancellable: cancellable, processor: processor, continuation: continuation)
            return true
        }
        guard adopted else {
            // Lost a start/start race: discard this pipeline without touching
            // the winner's tap (the cancellation guard skips the teardown).
            cancellable.cancel()
            processor.cancel()
            continuation.finish()
            return
        }
    }

    public func stop() {
        let stopped = pipeline.withLockUnchecked { state in
            defer { state = Pipeline() }
            return state
        }
        stopped.cancellable?.cancel()
        stopped.continuation?.finish()
    }

    public func magnitudes() -> [Float] {
        let samples = tap.latestSamples(count: spectrumStyle.fftSize)
        guard !samples.isEmpty else { return [] }
        return analyzer.magnitudes(of: samples)
    }
}
