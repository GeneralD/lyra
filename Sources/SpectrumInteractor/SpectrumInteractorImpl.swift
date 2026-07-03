import Combine
import Dependencies
import Domain
import Foundation
import FrequencyAnalyzer
import os

/// Drives the spectrum analyzer (#23): follows the now-playing stream, keeps
/// the CoreAudio process tap scoped to the now-playing app, and converts the
/// captured PCM window into per-bar magnitudes on demand.
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
    // Stored wrappers capture the dependency context at init, so instances
    // built inside `withDependencies` keep their fakes when methods run
    // outside that scope (the processor task).
    @Dependency(\.configUseCase) private var configService
    @Dependency(\.playbackUseCase) private var playbackService
    @Dependency(\.audioTapDataSource) private var tap
    private let capturingSubject = CurrentValueSubject<Bool, Never>(false)
    private let processor = OSAllocatedUnfairLock(initialState: Task<Void, Never>?.none)
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
        let playback = playbackService
        // A single for-await loop is the serialization point: events apply
        // one at a time, so a rapid pause→play burst can never interleave tap
        // create/destroy calls. `previous` dedupes the helper's periodic
        // ticks — `startTap` rebuilds the engine, so repeats must not pass.
        let candidate = Task {
            var previous: AudioSourceState?
            for await info in playback.observeNowPlaying() {
                let source = AudioSourceState(
                    pid: info?.pid, isPlaying: (info?.playbackRate ?? 0) > 0)
                guard source != previous else { continue }
                previous = source
                guard let pid = source.pid, source.isPlaying else {
                    await tap.stopTap()
                    subject.send(false)
                    continue
                }
                subject.send(await tap.startTap(pid: pid))
            }
            // Upstream finished (helper EOF): tear the tap down. A cancelled
            // task skips this — stop() owns that teardown, and a start/start
            // race loser must not destroy the winner's tap.
            guard !Task.isCancelled else { return }
            await tap.stopTap()
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
        let tap = tap
        let subject = capturingSubject
        Task {
            // Awaiting the cancelled processor first keeps this teardown
            // ordered after its in-flight tap call.
            await stopped.value
            await tap.stopTap()
            subject.send(false)
        }
    }

    public func magnitudes() -> [Float] {
        let samples = tap.latestSamples(count: spectrumStyle.fftSize)
        guard !samples.isEmpty else { return [] }
        return analyzer.magnitudes(of: samples)
    }
}
